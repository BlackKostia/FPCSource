{ async/await as a heap state machine.
  See docs/concurrency/guides/statemachine.md }
program statemachine;

{$mode objfpc}{$H+}
{$modeswitch functionreferences}
{$ASYNCMODE STATEMACHINE}

uses
  {$ifdef unix}cthreads,{$endif}
  SysUtils, System.Threading;

{ Returns before either delay has finished. Result is the inner Integer,
  not the future: the generated code publishes the future. }
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

{ An already completed task does not suspend the step. }
function Already(const Done: specialize IFuture<Integer>): specialize IFuture<Integer>; async;
begin
  Result := await Done;
end;

var
  Src: specialize TTaskCompletionSource<Integer>;
  F: specialize IFuture<Integer>;
  T0: QWord;
begin
  T0 := GetTickCount64;
  F := Pipeline;
  if GetTickCount64 - T0 >= 50 then
    Halt(1);
  if F.Status = TTaskStatus.Completed then
    Halt(2);
  if F.Value <> 42 then
    Halt(3);

  Src := specialize TTaskCompletionSource<Integer>.Create;
  try
    Src.SetResult(7);
    { SetResult queues the task body, so wait until that body has finished. }
    while Src.Task.Status <> TTaskStatus.Completed do
      Sleep(1);
    F := Already(Src.Task);
    if F.Value <> 7 then
      Halt(4);
  finally
    Src.Free;
  end;
  Writeln('ok');
end.
