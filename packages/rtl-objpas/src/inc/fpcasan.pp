{
    This file is part of the Free Pascal run time library.
    Copyright (c) 2026 by the Free Pascal development team

    Run time support for code compiled with -fsanitize=address
    (AddressSanitizer, x86_64-linux). The compiler adds
    this unit to every module compiled with the option and calls the
    trampolines below before each instrumented memory access.

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

 **********************************************************************}
{$IFNDEF FPC_DOTTEDUNITS}
unit fpcasan;
{$ENDIF FPC_DOTTEDUNITS}

{$mode objfpc}
{ the unit itself must never be instrumented: the trampolines would call
  themselves }
{$if defined(FPC_SANITIZE_THREAD) or defined(FPC_SANITIZE_ADDRESS)}
  {$error fpcasan must be compiled without -fsanitize}
{$endif}
{$if defined(CPUX86_64) and defined(LINUX)}
  {$define FPC_ASAN_SUPPORTED}
{$endif}

interface

{ Marks the memory range as not addressable / addressable again, for
  custom allocators that keep freed blocks (pools, free lists, arenas):
  an instrumented access to a poisoned range is reported like an access to
  freed heap memory. No-ops when the program does not run under
  AddressSanitizer. }
procedure AsanPoison(aAddr: Pointer; aSize: PtrUInt);
procedure AsanUnpoison(aAddr: Pointer; aSize: PtrUInt);

{ Returns whether the instrumented code would report an access to the
  range (some byte of it is not addressable) }
function AsanIsPoisoned(aAddr: Pointer; aSize: PtrUInt): Boolean;

implementation

{$ifdef FPC_ASAN_SUPPORTED}

{$linklib asan}

function asan_region_is_poisoned(aAddr: Pointer; aSize: PtrUInt): Pointer; cdecl; external name '__asan_region_is_poisoned';
procedure asan_poison_memory_region(aAddr: Pointer; aSize: PtrUInt); cdecl; external name '__asan_poison_memory_region';
procedure asan_unpoison_memory_region(aAddr: Pointer; aSize: PtrUInt); cdecl; external name '__asan_unpoison_memory_region';
{ report the error and abort; the pc of the access is their return address }
procedure asan_report_load_n(aAddr: Pointer; aSize: PtrUInt); cdecl; external name '__asan_report_load_n';
procedure asan_report_store_n(aAddr: Pointer; aSize: PtrUInt); cdecl; external name '__asan_report_store_n';

{ the slow path of the trampolines: the access touches a partially
  addressable granule, or is larger than 16 bytes }
function AsanCheck(aAddr: Pointer; aSize: PtrUInt): Boolean;
begin
  Result := asan_region_is_poisoned(aAddr, aSize) <> nil;
end;

{$asmmode att}

{ Instrumented code calls the trampolines with

    rdi = address of the access, esi = size in bytes,
    [rsp] = return address (a pc inside the instrumentation),
    [rsp+8] = saved rsi, [rsp+16] = saved rdi, and the red zone of 128
    bytes above them.

  The trampolines preserve all registers, the flags and xmm0..xmm15. The
  shadow byte of an 8-byte granule at (addr shr 3) + $7fff8000 is 0 when
  the whole granule is addressable: an access of up to 16 bytes is valid
  if the shadow bytes of its first and last granule (and the one between)
  are 0. Otherwise __asan_region_is_poisoned decides. A bad access is
  reported by __asan_report_load_n/store_n entered as if it were called at
  the access: with the stack pointer of the instrumented code and the pc
  of the access as return address, so that both the frame pointer and the
  DWARF unwinder of ASan show the stack of the program. }

procedure fpc_asan_check; assembler; nostackframe;
asm
  { [rsp] = saved rdx, edx = kind (0 read, 1 write) }
  pushfq
  pushq %rax
  pushq %rcx
  cmpl  $16,%esi
  ja    .Lslow
  movq  %rdi,%rax
  shrq  $3,%rax
  movsbl 0x7fff8000(%rax),%ecx
  testl %ecx,%ecx
  jnz   .Lslow
  leaq  -1(%rdi,%rsi),%rax
  shrq  $3,%rax
  movsbl 0x7fff8000(%rax),%ecx
  testl %ecx,%ecx
  jnz   .Lslow
  cmpl  $8,%esi
  jbe   .Lok
  leaq  8(%rdi),%rax
  shrq  $3,%rax
  movsbl 0x7fff8000(%rax),%ecx
  testl %ecx,%ecx
  jnz   .Lslow
.Lok:
  popq  %rcx
  popq  %rax
  popfq
  popq  %rdx
  ret
.Lslow:
  popq  %rcx
  popq  %rax
  popfq
  { [rbx] = rbx, [rbx+8] = rdx, [rbx+16] = return address, [rbx+24] = rsi
    and [rbx+32] = rdi of the program, the stack pointer of the program
    is rbx+40+128; [rbx-64] = address, [rbx-72] = size, [rbx-80] = kind }
  pushq %rbx
  movq  %rsp,%rbx
  pushfq
  pushq %rax
  pushq %rcx
  pushq %r8
  pushq %r9
  pushq %r10
  pushq %r11
  pushq %rdi
  pushq %rsi
  pushq %rdx
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
  movl  %esi,%esi
  call  AsanCheck
  testb %al,%al
  jnz   .Lreport
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
  leaq  -80(%rbx),%rsp
  popq  %rdx
  popq  %rsi
  popq  %rdi
  popq  %r11
  popq  %r10
  popq  %r9
  popq  %r8
  popq  %rcx
  popq  %rax
  popfq
  popq  %rbx
  popq  %rdx
  ret
.Lreport:
  movq  -64(%rbx),%rdi
  movl  -72(%rbx),%esi
  movq  -80(%rbx),%rdx
  movq  16(%rbx),%rcx
  leaq  168(%rbx),%rax
  movq  (%rbx),%rbx
  movq  %rax,%rsp
  { the report function expects rsp+8 to be 16-byte aligned at its entry;
    the instrumented code may have an unaligned stack (a leaf procedure
    without a stack frame), then the pc is pushed twice }
  testq $15,%rsp
  jz    .Lone
  pushq %rcx
.Lone:
  pushq %rcx
  testq %rdx,%rdx
  jnz   .Lstore
  jmp   asan_report_load_n
.Lstore:
  jmp   asan_report_store_n
end;

procedure fpc_asan_read; assembler; nostackframe; public name 'FPC_ASAN_READ';
asm
  pushq %rdx
  movl  $0,%edx
  jmp   fpc_asan_check
end;

procedure fpc_asan_write; assembler; nostackframe; public name 'FPC_ASAN_WRITE';
asm
  pushq %rdx
  movl  $1,%edx
  jmp   fpc_asan_check
end;

procedure AsanPoison(aAddr: Pointer; aSize: PtrUInt);
begin
  asan_poison_memory_region(aAddr, aSize);
end;

procedure AsanUnpoison(aAddr: Pointer; aSize: PtrUInt);
begin
  asan_unpoison_memory_region(aAddr, aSize);
end;

function AsanIsPoisoned(aAddr: Pointer; aSize: PtrUInt): Boolean;
begin
  Result := asan_region_is_poisoned(aAddr, aSize) <> nil;
end;

{$else FPC_ASAN_SUPPORTED}

procedure AsanPoison(aAddr: Pointer; aSize: PtrUInt);
begin
end;

procedure AsanUnpoison(aAddr: Pointer; aSize: PtrUInt);
begin
end;

function AsanIsPoisoned(aAddr: Pointer; aSize: PtrUInt): Boolean;
begin
  Result := False;
end;

{$endif FPC_ASAN_SUPPORTED}

end.
