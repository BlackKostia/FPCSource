{ %OPT=-fsanitize=thread -Cg }
{ %TARGET=linux }
{ %CPU=x86_64 }
{ %NORUN }
{ code instrumented for ThreadSanitizer: many kinds of memory accesses
  as position independent code (-Cg)
  (the instrumented programs need "setarch -R" on current kernels, so they
  are run by tests/concurrency/run-tsan.sh instead) }
program ttsan2;

{$mode objfpc}{$H+}
{$asmmode att}

{$ifndef FPC_SANITIZE_THREAD}
  {$error FPC_SANITIZE_THREAD is not defined}
{$endif}

uses
  {$ifdef unix}cthreads,{$endif} SysUtils;

type
  TRec = record
    A: array[0..15] of LongInt;
    S: ShortString;
    D: Double;
  end;

  TBase = class
    F: Int64;
    procedure Bump; virtual;
  end;

  TDerived = class(TBase)
    procedure Bump; override;
  end;

  generic TBox<T> = record
    Value: T;
  end;

threadvar
  TV: LongInt;

var
  G: Int64;
  R1, R2: TRec;
  E: Extended;
  S: Single;
  Str: AnsiString;
  WS: UnicodeString;
  Bits: set of Byte;
  Arr: array of Word;
  Obj: TBase;
  Box: specialize TBox<Double>;

procedure TBase.Bump;
begin
  Inc(F);
end;

procedure TDerived.Bump;
begin
  inherited Bump;
  F := F * 2;
end;

function Outer(X: LongInt): LongInt;

  function Inner: LongInt;
  begin
    Result := X * 2 + G;
  end;

begin
  Result := Inner;
end;

function AsmBlock(P: PInt64): Int64; assembler; nostackframe;
asm
  movq (%rdi),%rax
  addq $1,%rax
  movq %rax,(%rdi)
end;

procedure InlineAsm(P: PInt64);
begin
  asm
    movq P,%rax
    incq (%rax)
  end;
end;

begin
  G := 1;
  TV := 5;
  R1.A[3] := 7;
  R1.S := 'abc';
  R1.D := 1.5;
  R2 := R1;
  E := Sqrt(2.0) * 3;
  S := E;
  Str := 'x' + IntToStr(R2.A[3]);
  WS := UnicodeString(Str);
  Bits := [1, 3, 200];
  SetLength(Arr, 10);
  Arr[5] := Word(Length(WS));
  Obj := TDerived.Create;
  Obj.Bump;
  Box.Value := R1.D * 2;
  G := Outer(3) + AsmBlock(@G) + TV;
  InlineAsm(@G);
  try
    if 200 in Bits then
      raise Exception.Create('test');
  except
    on Ex: Exception do
      Str := Ex.Message;
  end;
  Obj.Free;
end.
