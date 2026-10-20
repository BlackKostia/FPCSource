{
    This file is part of the Free Pascal run time library.
    Copyright (c) 2026 by the Free Pascal development team

    Run time support for code compiled with -fsanitize=thread
    (ThreadSanitizer, x86_64-linux). The compiler adds this unit to every
    module compiled with the option and calls the trampolines below before
    each instrumented memory access.

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

 **********************************************************************}
{$IFNDEF FPC_DOTTEDUNITS}
unit fpctsan;
{$ENDIF FPC_DOTTEDUNITS}

{$mode objfpc}
{ the unit itself must never be instrumented }
{$if defined(CPUX86_64) and defined(LINUX)}
  {$define FPC_TSAN_SUPPORTED}
{$endif}

interface

{ Orders memory accesses for ThreadSanitizer, like fpvalgrind's
  VgHappensBefore/VgHappensAfter: everything before TsanRelease(Addr) in
  one thread happens before everything after a later TsanAcquire(Addr) in
  another. Needed for synchronization through atomic operations of the
  RTL (InterlockedXxx), which are not instrumented. No-ops when the
  program does not run under ThreadSanitizer. }
procedure TsanRelease(aAddr: Pointer);
procedure TsanAcquire(aAddr: Pointer);

implementation

{$ifdef FPC_TSAN_SUPPORTED}

{$linklib tsan}
{$asmmode att}

procedure tsan_read1_pc(aAddr, aPC: Pointer); cdecl; external name '__tsan_read1_pc';
procedure tsan_read2_pc(aAddr, aPC: Pointer); cdecl; external name '__tsan_read2_pc';
procedure tsan_read4_pc(aAddr, aPC: Pointer); cdecl; external name '__tsan_read4_pc';
procedure tsan_read8_pc(aAddr, aPC: Pointer); cdecl; external name '__tsan_read8_pc';
procedure tsan_read16_pc(aAddr, aPC: Pointer); cdecl; external name '__tsan_read16_pc';
procedure tsan_read_range_pc(aAddr: Pointer; aSize: PtrUInt; aPC: Pointer); cdecl; external name '__tsan_read_range_pc';
procedure tsan_write1_pc(aAddr, aPC: Pointer); cdecl; external name '__tsan_write1_pc';
procedure tsan_write2_pc(aAddr, aPC: Pointer); cdecl; external name '__tsan_write2_pc';
procedure tsan_write4_pc(aAddr, aPC: Pointer); cdecl; external name '__tsan_write4_pc';
procedure tsan_write8_pc(aAddr, aPC: Pointer); cdecl; external name '__tsan_write8_pc';
procedure tsan_write16_pc(aAddr, aPC: Pointer); cdecl; external name '__tsan_write16_pc';
procedure tsan_write_range_pc(aAddr: Pointer; aSize: PtrUInt; aPC: Pointer); cdecl; external name '__tsan_write_range_pc';
procedure tsan_acquire(aAddr: Pointer); cdecl; external name '__tsan_acquire';
procedure tsan_release(aAddr: Pointer); cdecl; external name '__tsan_release';

{ Instrumented code calls the trampolines with

    rdi = address of the access, esi = size in bytes, [rsp] = return address
          (a pc inside the instrumentation of the access)

  after saving rdi and rsi itself and skipping the red zone. The
  trampolines preserve all other registers, the flags and xmm0..xmm15, as
  the instrumented code does not expect a call there; rbx (callee-saved)
  holds the stack pointer at entry. }

procedure fpc_tsan_read; assembler; nostackframe; public name 'FPC_TSAN_READ';
asm
  pushq %rbx
  movq  %rsp,%rbx
  pushfq
  pushq %rax
  pushq %rcx
  pushq %rdx
  pushq %r8
  pushq %r9
  pushq %r10
  pushq %r11
  andq  $-16,%rsp
  subq  $256,%rsp
  movdqu %xmm0,(%rsp)
  movdqu %xmm1,16(%rsp)
  movdqu %xmm2,32(%rsp)
  movdqu %xmm3,48(%rsp)
  movdqu %xmm4,64(%rsp)
  movdqu %xmm5,80(%rsp)
  movdqu %xmm6,96(%rsp)
  movdqu %xmm7,112(%rsp)
  movdqu %xmm8,128(%rsp)
  movdqu %xmm9,144(%rsp)
  movdqu %xmm10,160(%rsp)
  movdqu %xmm11,176(%rsp)
  movdqu %xmm12,192(%rsp)
  movdqu %xmm13,208(%rsp)
  movdqu %xmm14,224(%rsp)
  movdqu %xmm15,240(%rsp)
  cld
  movl  %esi,%eax
  movq  8(%rbx),%rsi
  cmpl  $8,%eax
  je    .Lr8
  cmpl  $4,%eax
  je    .Lr4
  cmpl  $1,%eax
  je    .Lr1
  cmpl  $2,%eax
  je    .Lr2
  cmpl  $16,%eax
  je    .Lr16
  movq  %rsi,%rdx
  movl  %eax,%esi
  call  tsan_read_range_pc
  jmp   .Ldone
.Lr8:
  call  tsan_read8_pc
  jmp   .Ldone
.Lr4:
  call  tsan_read4_pc
  jmp   .Ldone
.Lr1:
  call  tsan_read1_pc
  jmp   .Ldone
.Lr2:
  call  tsan_read2_pc
  jmp   .Ldone
.Lr16:
  call  tsan_read16_pc
.Ldone:
  movdqu (%rsp),%xmm0
  movdqu 16(%rsp),%xmm1
  movdqu 32(%rsp),%xmm2
  movdqu 48(%rsp),%xmm3
  movdqu 64(%rsp),%xmm4
  movdqu 80(%rsp),%xmm5
  movdqu 96(%rsp),%xmm6
  movdqu 112(%rsp),%xmm7
  movdqu 128(%rsp),%xmm8
  movdqu 144(%rsp),%xmm9
  movdqu 160(%rsp),%xmm10
  movdqu 176(%rsp),%xmm11
  movdqu 192(%rsp),%xmm12
  movdqu 208(%rsp),%xmm13
  movdqu 224(%rsp),%xmm14
  movdqu 240(%rsp),%xmm15
  leaq  -64(%rbx),%rsp
  popq  %r11
  popq  %r10
  popq  %r9
  popq  %r8
  popq  %rdx
  popq  %rcx
  popq  %rax
  popfq
  popq  %rbx
end;

procedure fpc_tsan_write; assembler; nostackframe; public name 'FPC_TSAN_WRITE';
asm
  pushq %rbx
  movq  %rsp,%rbx
  pushfq
  pushq %rax
  pushq %rcx
  pushq %rdx
  pushq %r8
  pushq %r9
  pushq %r10
  pushq %r11
  andq  $-16,%rsp
  subq  $256,%rsp
  movdqu %xmm0,(%rsp)
  movdqu %xmm1,16(%rsp)
  movdqu %xmm2,32(%rsp)
  movdqu %xmm3,48(%rsp)
  movdqu %xmm4,64(%rsp)
  movdqu %xmm5,80(%rsp)
  movdqu %xmm6,96(%rsp)
  movdqu %xmm7,112(%rsp)
  movdqu %xmm8,128(%rsp)
  movdqu %xmm9,144(%rsp)
  movdqu %xmm10,160(%rsp)
  movdqu %xmm11,176(%rsp)
  movdqu %xmm12,192(%rsp)
  movdqu %xmm13,208(%rsp)
  movdqu %xmm14,224(%rsp)
  movdqu %xmm15,240(%rsp)
  cld
  movl  %esi,%eax
  movq  8(%rbx),%rsi
  cmpl  $8,%eax
  je    .Lw8
  cmpl  $4,%eax
  je    .Lw4
  cmpl  $1,%eax
  je    .Lw1
  cmpl  $2,%eax
  je    .Lw2
  cmpl  $16,%eax
  je    .Lw16
  movq  %rsi,%rdx
  movl  %eax,%esi
  call  tsan_write_range_pc
  jmp   .Lwdone
.Lw8:
  call  tsan_write8_pc
  jmp   .Lwdone
.Lw4:
  call  tsan_write4_pc
  jmp   .Lwdone
.Lw1:
  call  tsan_write1_pc
  jmp   .Lwdone
.Lw2:
  call  tsan_write2_pc
  jmp   .Lwdone
.Lw16:
  call  tsan_write16_pc
.Lwdone:
  movdqu (%rsp),%xmm0
  movdqu 16(%rsp),%xmm1
  movdqu 32(%rsp),%xmm2
  movdqu 48(%rsp),%xmm3
  movdqu 64(%rsp),%xmm4
  movdqu 80(%rsp),%xmm5
  movdqu 96(%rsp),%xmm6
  movdqu 112(%rsp),%xmm7
  movdqu 128(%rsp),%xmm8
  movdqu 144(%rsp),%xmm9
  movdqu 160(%rsp),%xmm10
  movdqu 176(%rsp),%xmm11
  movdqu 192(%rsp),%xmm12
  movdqu 208(%rsp),%xmm13
  movdqu 224(%rsp),%xmm14
  movdqu 240(%rsp),%xmm15
  leaq  -64(%rbx),%rsp
  popq  %r11
  popq  %r10
  popq  %r9
  popq  %r8
  popq  %rdx
  popq  %rcx
  popq  %rax
  popfq
  popq  %rbx
end;

procedure TsanRelease(aAddr: Pointer);
begin
  tsan_release(aAddr);
end;

procedure TsanAcquire(aAddr: Pointer);
begin
  tsan_acquire(aAddr);
end;

{$else FPC_TSAN_SUPPORTED}

procedure TsanRelease(aAddr: Pointer);
begin
end;

procedure TsanAcquire(aAddr: Pointer);
begin
end;

{$endif FPC_TSAN_SUPPORTED}

end.
