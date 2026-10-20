{
    Copyright (c) 2026 by the Free Pascal development team

    ThreadSanitizer instrumentation of the generated x86_64 code
    (-fsanitize=thread)

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program; if not, write to the Free Software
    Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

 ****************************************************************************
}
unit tsaninstr;

{$i fpcdefs.inc}

interface

uses
  aasmdata;

{ Inserts a call of a ThreadSanitizer trampoline (unit fpctsan) before
  every instruction of the procedure code in list that accesses memory
  which may be shared between threads. Runs after register allocation and
  the optimizer, on the final instructions, so it sees every memory access
  of the generated code; the trampolines preserve all registers and the
  flags. Not instrumented: accesses relative to the stack or frame pointer
  (the frame of the procedure), thread-local accesses (segment override),
  GOT loads, atomic instructions (lock/xacquire/xrelease prefix, xchg with
  memory), the targets of calls and jumps, lea and prefetches, and inline
  assembler blocks. }
procedure tsan_instrument(list: TAsmList);

implementation

uses
  globtype,globals,systems,
  aasmbase,aasmtai,aasmcpu,
  cpubase,cgbase,cgutils,procinfo;

const
  { leaf code may use the red zone below the stack pointer }
  redzone_size = 128;


function is_prefix(p: tai; out atomic: boolean): boolean;
  begin
    result:=false;
    atomic:=false;
    if (p.typ<>ait_instruction) then
      exit;
    case taicpu(p).opcode of
      A_LOCK,A_XACQUIRE,A_XRELEASE,
      { segment overrides: fs/gs are thread-local storage }
      A_SEGCS,A_SEGES,A_SEGDS,A_SEGFS,A_SEGGS,A_SEGSS:
        begin
          result:=true;
          atomic:=true;
        end;
      A_REP,A_REPE,A_REPNE,A_REPNZ,A_REPZ:
        result:=true;
      else
        ;
    end;
  end;


function not_an_access(op: tasmop): boolean;
  begin
    case op of
      A_LEA,A_NOP,
      A_PREFETCH,A_PREFETCHW,A_PREFETCHNTA,A_PREFETCHT0,A_PREFETCHT1,A_PREFETCHT2,
      A_CLFLUSH:
        result:=true;
      else
        result:=is_calljmp(op);
    end;
  end;


{ size in bytes of the memory operand opidx of p }
function access_size(p: taicpu; opidx: longint): longint;
  var
    i: longint;
  begin
    result:=0;
    case MemRefInfo(p.opcode).MemRefSize of
      msiMem8:
        result:=1;
      msiMem16,msiBMem16:
        result:=2;
      msiMem32,msiBMem32:
        result:=4;
      msiMem64,msiBMem64:
        result:=8;
      msiMem128:
        result:=16;
      msiMem256:
        result:=32;
      msiMem512:
        result:=64;
      msiMemRegSize:
        { same size as the register operand }
        for i:=0 to p.ops-1 do
          if (i<>opidx) and (p.oper[i]^.typ=top_reg) then
            begin
              result:=tcgsize2size[reg_cgsize(p.oper[i]^.reg)];
              break;
            end;
      else
        ;
    end;
    { general purpose and x87 instructions: the operand size suffix
      (for movzx/movsx the size of the source) }
    if result<=0 then
      result:=topsize2memsize[p.opsize] div 8;
    if result<=0 then
      for i:=0 to p.ops-1 do
        if (i<>opidx) and (p.oper[i]^.typ=top_reg) then
          begin
            result:=tcgsize2size[reg_cgsize(p.oper[i]^.reg)];
            break;
          end;
    if result<=0 then
      result:=1;
  end;


procedure insert_check(list: TAsmList; pos: tai; const ref: treference;
  size: longint; iswrite: boolean; const fileinfo: tfileposinfo);

  procedure add(ins: taicpu);
    begin
      ins.fileinfo:=fileinfo;
      list.insertbefore(ins,pos);
    end;

  var
    href,
    callref: treference;
    sym: tasmsymbol;
  begin
    { skip the red zone, save the registers used for the arguments }
    reference_reset_base(href,NR_STACK_POINTER_REG,-redzone_size,ctempposinvalid,sizeof(pint),[]);
    add(taicpu.op_ref_reg(A_LEA,S_Q,href,NR_STACK_POINTER_REG));
    add(taicpu.op_reg(A_PUSH,S_Q,NR_RDI));
    add(taicpu.op_reg(A_PUSH,S_Q,NR_RSI));
    { the address is computed before rdi/rsi are changed; references
      relative to the stack pointer are not instrumented }
    add(taicpu.op_ref_reg(A_LEA,S_Q,ref,NR_RDI));
    add(taicpu.op_const_reg(A_MOV,S_L,size,NR_ESI));
    if iswrite then
      sym:=current_asmdata.RefAsmSymbol('FPC_TSAN_WRITE',AT_FUNCTION)
    else
      sym:=current_asmdata.RefAsmSymbol('FPC_TSAN_READ',AT_FUNCTION);
    reference_reset_symbol(callref,sym,0,sizeof(pint),[]);
    if cs_create_pic in current_settings.moduleswitches then
      callref.refaddr:=addr_pic
    else
      callref.refaddr:=addr_full;
    add(taicpu.op_ref(A_CALL,S_NO,callref));
    add(taicpu.op_reg(A_POP,S_Q,NR_RSI));
    add(taicpu.op_reg(A_POP,S_Q,NR_RDI));
    reference_reset_base(href,NR_STACK_POINTER_REG,redzone_size,ctempposinvalid,sizeof(pint),[]);
    add(taicpu.op_ref_reg(A_LEA,S_Q,href,NR_STACK_POINTER_REG));
  end;


procedure instrument_instruction(list: TAsmList; p: taicpu);
  var
    i: longint;
    ref: preference;
    insertpos: tai;
    atomic: boolean;
  begin
    if not_an_access(p.opcode) then
      exit;
    { prefixes are separate instructions: insert before them; atomic and
      thread-local accesses are not instrumented }
    insertpos:=p;
    while assigned(insertpos.previous) and
          is_prefix(tai(insertpos.previous),atomic) do
      begin
        if atomic then
          exit;
        insertpos:=tai(insertpos.previous);
      end;
    for i:=0 to p.ops-1 do
      if p.oper[i]^.typ=top_ref then
        begin
          ref:=p.oper[i]^.ref;
          if (ref^.segment<>NR_NO) or
             (ref^.refaddr<>addr_no) or
             (ref^.base=NR_STACK_POINTER_REG) or
             (ref^.index=NR_STACK_POINTER_REG) or
             (ref^.base=current_procinfo.framepointer) then
            continue;
          { xchg with a memory operand is implicitly locked }
          if p.opcode=A_XCHG then
            exit;
          insert_check(list,insertpos,ref^,access_size(p,i),
            p.spilling_get_operation_type(i)<>operand_read,p.fileinfo);
        end;
  end;


procedure tsan_instrument(list: TAsmList);
  var
    p,
    next: tai;
    inasm: boolean;
  begin
    inasm:=false;
    p:=tai(list.first);
    while assigned(p) do
      begin
        next:=tai(p.next);
        case p.typ of
          ait_marker:
            case tai_marker(p).kind of
              mark_AsmBlockStart:
                inasm:=true;
              mark_AsmBlockEnd:
                inasm:=false;
              else
                ;
            end;
          ait_instruction:
            if not inasm then
              instrument_instruction(list,taicpu(p));
          else
            ;
        end;
        p:=next;
      end;
  end;

end.
