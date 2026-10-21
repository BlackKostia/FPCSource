program test_statemachine_async;

{ $ASYNCMODE STATEMACHINE lowers async routines to a heap state machine.
  The call returns a task before any awaited delay has finished. }

{$mode objfpc}{$H+}
{$modeswitch functionreferences}
{$modeswitch anonymousfunctions}
{$ASYNCMODE STATEMACHINE}

uses
  {$ifdef unix}cthreads,{$endif}
  SysUtils, System.Threading;

var
  Passed, Failed: Integer;
  FinallyFlag: Integer;

procedure Check(const Msg: string; Ok: Boolean);
begin
  if Ok then
    begin
      Inc(Passed);
      Writeln('  [PASS] ', Msg);
    end
  else
    begin
      Inc(Failed);
      Writeln('  [FAIL] ', Msg);
    end;
end;

function Pipeline: specialize IFuture<Integer>; async;
var
  N: Integer;
begin
  N := 1;
  await TTask.Delay(200);
  N := N + 1;
  await TTask.Delay(200);
  Result := N + 40;
end;

function AlreadyDone: specialize IFuture<Integer>; async;
var
  Src: specialize TTaskCompletionSource<Integer>;
begin
  Src := specialize TTaskCompletionSource<Integer>.Create;
  Src.SetResult(7);
  { SetResult queues the task body, so wait until that body has finished.
    The await itself must then continue without suspending. }
  while Src.Task.Status <> TTaskStatus.Completed do
    Sleep(1);
  Result := await Src.Task;
  Src.Free;
end;

function Faulted: specialize IFuture<Integer>; async;
var
  Src: specialize TTaskCompletionSource<Integer>;
begin
  Src := specialize TTaskCompletionSource<Integer>.Create;
  Src.SetException(Exception.Create('boom'));
  Result := await Src.Task;
  Src.Free;
end;

function Caught: specialize IFuture<Integer>; async;
var
  Src: specialize TTaskCompletionSource<Integer>;
begin
  Src := specialize TTaskCompletionSource<Integer>.Create;
  Src.SetException(Exception.Create('boom'));
  try
    Result := await Src.Task;
  except
    Result := -1;
  end;
  Src.Free;
end;

function Raises: specialize IFuture<Integer>; async;
begin
  raise Exception.Create('plain');
  Result := 1;
end;

function Branch(N: Integer): specialize IFuture<Integer>; async;
begin
  if N > 0 then
    begin
      await TTask.Delay(30);
      Result := 1;
    end
  else
    begin
      await TTask.Delay(30);
      Result := 2;
    end;
end;

function CountDown: specialize IFuture<Integer>; async;
var
  I, S: Integer;
begin
  I := 3;
  S := 0;
  while I > 0 do
    begin
      await TTask.Delay(15);
      S := S + I;
      Dec(I);
    end;
  Result := S;
end;

function SumFor: specialize IFuture<Integer>; async;
var
  I, S: Integer;
begin
  S := 0;
  for I := 1 to 3 do
    begin
      await TTask.Delay(15);
      S := S + I;
    end;
  Result := S;
end;

function BreakAt: specialize IFuture<Integer>; async;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to 5 do
    begin
      await TTask.Delay(10);
      if I = 3 then
        break;
      Result := Result + I;
    end;
end;

function Early: specialize IFuture<Integer>; async;
begin
  await TTask.Delay(20);
  Result := 5;
  Exit;
  Result := 9;
end;

function WithFinally: specialize IFuture<Integer>; async;
begin
  try
    await TTask.Delay(200);
  finally
    FinallyFlag := 1;
  end;
  Result := FinallyFlag;
end;

function Sticky: specialize IFuture<string>; async;
var
  S: string;
begin
  S := 'ab';
  await TTask.Delay(20);
  Result := S + 'c';
end;

function WaitValue(const F: specialize IFuture<Integer>): Integer;
begin
  Result := F.Value;
end;

var
  F: specialize IFuture<Integer>;
  FS: specialize IFuture<string>;
  T0, Took: QWord;
  Saw: Boolean;
begin
  Passed := 0;
  Failed := 0;

  Writeln('--- pipeline returns before the delays ---');
  T0 := GetTickCount64;
  F := Pipeline;
  Took := GetTickCount64 - T0;
  Check('call returns in under 50ms', Took < 50);
  Check('future is not complete yet', F.Status <> TTaskStatus.Completed);
  Check('two awaits yield 42', WaitValue(F) = 42);

  Writeln('--- already complete task does not suspend ---');
  T0 := GetTickCount64;
  F := AlreadyDone;
  Took := GetTickCount64 - T0;
  { SetResult starts the result task; its body runs on the pool, so the
    status here is WaitingToRun rather than Completed. Created would mean
    the await suspended and the result was not published yet. }
  Check('completed future is ready at once', F.Status <> TTaskStatus.Created);
  Check('value is 7', F.Value = 7);
  Check('no delay', Took < 50);

  Writeln('--- faulted task fails the future ---');
  F := Faulted;
  Saw := False;
  try
    if F.Value = 0 then
      ;
  except
    Saw := True;
  end;
  Check('reading a faulted future raises', Saw);

  Writeln('--- except in the body sees the fault ---');
  F := Caught;
  Check('handler result is -1', WaitValue(F) = -1);

  Writeln('--- a raise faults the future ---');
  F := Raises;
  Saw := False;
  try
    if F.Value = 0 then
      ;
  except
    Saw := True;
  end;
  Check('plain raise faults the future', Saw);

  Writeln('--- if, while, for, break, exit ---');
  Check('then branch', WaitValue(Branch(1)) = 1);
  Check('else branch', WaitValue(Branch(0)) = 2);
  Check('while sums 6', WaitValue(CountDown) = 6);
  Check('for sums 6', WaitValue(SumFor) = 6);
  Check('break stops at 3', WaitValue(BreakAt) = 3);
  Check('exit keeps 5', WaitValue(Early) = 5);

  Writeln('--- finally does not run at the suspension ---');
  FinallyFlag := 0;
  F := WithFinally;
  Check('flag still clear before the delay', FinallyFlag = 0);
  Check('finally ran once the task finished', WaitValue(F) = 1);
  Check('flag is set afterwards', FinallyFlag = 1);

  Writeln('--- a managed local survives await ---');
  FS := Sticky;
  Check('string is abc', FS.Value = 'abc');

  Writeln(Passed, ' passed, ', Failed, ' failed');
  if Failed <> 0 then
    Halt(1);
end.
