program test_await_operator;

{ The await operator: "await E" reads E.Value when E has a Value member
  (IFuture<T>), otherwise calls E.Wait (ITask). It blocks the current
  thread until E is complete. }

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


function SlowAnswerAsync: specialize IFuture<Integer>; async;
begin
  Result := TTask.specialize Future<Integer>(
    function: Integer
    begin      
      Sleep(100);
      Result := 42;
    end);
end;

procedure TestValue;
var
  V: Integer;
  T0: QWord;
begin
  T0 := GetTickCount64;
  V := await SlowAnswerAsync;
  Check('await IFuture<T> gives the value', V = 42);
  Check('await waits for the future (blocking)', GetTickCount64 - T0 >= 90);
end;

procedure TestTask;
var
  T: ITask;
  Done: Boolean;
begin
  Done := False;
  T := TTask.Run(procedure begin Sleep(50); Done := True; end);
  await T;
  Check('await ITask waits for completion', Done);
end;

procedure TestException;
var
  F: specialize IFuture<Integer>;
  Caught: Boolean;
begin
  F := TTask.specialize Future<Integer>(
    function: Integer
    begin
      raise Exception.Create('boom');
    end);
  Caught := False;
  try
    await F;
  except
    on E: EAggregateException do
      Caught := E.InnerExceptions[0].Message = 'boom';
  end;
  Check('await re-raises the exception of a faulted future', Caught);
end;

begin
  Writeln('=== await operator ===');
  TestValue;
  TestTask;
  TestException;
  Writeln('Passed: ', TestsPassed, ', Failed: ', TestsFailed);
  if TestsFailed > 0 then
    Halt(1);
end.
