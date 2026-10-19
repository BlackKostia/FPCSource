program test_await_identifier;

{ "await" is a contextual keyword. Code that uses "await" as an ordinary
  identifier (as was legal before async/await was added) must keep
  compiling and meaning what it meant; where no such identifier is in scope,
  "await" is the operator. }

{$mode objfpc}{$H+}
{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}

uses
  {$ifdef unix}cthreads,{$endif}
  SysUtils, System.Threading;

var
  TestsPassed: Integer = 0;
  TestsFailed: Integer = 0;

procedure Check(const Msg: string; Condition: Boolean);
begin
  if Condition then
  begin
    Inc(TestsPassed);
    Writeln('  [PASS] ', Msg);
  end
  else
  begin
    Inc(TestsFailed);
    Writeln('  [FAIL] ', Msg);
  end;
end;

type
  TTimer = record
    await: Integer; { a field named await }
  end;

procedure LocalVariable;
var
  await: Integer;
begin
  await := 3;
  await := await + 1;
  Check('local variable named await', await = 4);
end;

function await(X: Integer): Integer;
begin
  Result := X * 2;
end;

procedure FunctionNamedAwait;
begin
  Check('function named await is called', await(21) = 42);
end;

procedure FieldNamedAwait;
var
  T: TTimer;
begin
  T.await := 5;
  Check('record field named await', T.await = 5);
end;

begin
  Writeln('=== await as an identifier ===');
  LocalVariable;
  FunctionNamedAwait;
  FieldNamedAwait;
  Writeln('Passed: ', TestsPassed, ', Failed: ', TestsFailed);
  if TestsFailed > 0 then
    Halt(1);
end.
