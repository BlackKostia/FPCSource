{ {$modeswitch inlinevars}: repeat .. until, try blocks, nested and
  generic routines, anonymous functions, initialization of a unit-like
  main block }
{$mode objfpc}{$H+}
{$modeswitch inlinevars}
{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}
program tinlinevar4;

uses
  SysUtils;

type
  TIntFunc = reference to function: Integer;

procedure Check(Cond: Boolean; Code: Integer);
begin
  if not Cond then
    begin
      WriteLn('failed ', Code);
      Halt(Code);
    end;
end;

generic function Pair<T>(const A, B: T): string;
begin
  var First: T := A;
  var Second := B;
  Result := First + '/' + Second;
end;

function Outer(N: Integer): Integer;

  function Inner: Integer;
  begin
    var Local := N * 10;
    Result := Local + 1;
  end;

begin
  var Base := Inner;
  Result := Base + N;
end;

function MakeCounter: TIntFunc;
begin
  var Count := 0;
  Result := function: Integer
    begin
      Inc(Count);
      Result := Count;
    end;
end;

var
  Steps: Integer;
  F: TIntFunc;
begin
  { variables of the body of repeat are visible in the condition }
  Steps := 0;
  repeat
    var Next := Steps + 1;
    Steps := Next;
  until Next >= 3;
  Check(Steps = 3, 1);

  try
    var InTry := 'try';
    Check(InTry = 'try', 2);
  finally
    var InFinally := 'finally';
    Check(InFinally = 'finally', 3);
  end;

  try
    raise Exception.Create('boom');
  except
    var Handled := True;
    Check(Handled, 4);
  end;

  Check(specialize Pair<string>('a', 'b') = 'a/b', 5);
  Check(Outer(2) = 23, 6);

  F := MakeCounter();
  F();
  Check(F() = 2, 7);

  case Steps of
    3:
      begin
        var InCase := Steps * 2;
        Check(InCase = 6, 8);
      end;
  end;
  WriteLn('ok');
end.
