program test_unobserved_exception_fiber;

{$mode objfpc}{$H+}
{$modeswitch functionreferences}
{$modeswitch anonymousfunctions}
{$ASYNCMODE FIBER}

uses
  {$ifdef unix}cthreads,{$endif}
  SysUtils, System.Threading, fclasync;

var
  Passed, Failed: Integer;
  UnobservedCount: Integer = 0;
  LastExceptionMsg: string = '';

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

procedure GlobalUnobservedHandler(const ATask: ITask; AException: Exception);
begin
  Inc(UnobservedCount);
  if Assigned(AException) then
    LastExceptionMsg := AException.Message
  else
    LastExceptionMsg := '';
end;

{ 1. Fire-and-forget async procedure that faults }
procedure FireAndForgetFault; async;
begin
  await TTask.Delay(10);
  raise Exception.Create('Intentional fiber fire-and-forget error');
end;

{ 2. Awaited async function that faults - should NOT trigger unobserved hook }
function AwaitedFault: specialize IFuture<Integer>; async;
begin
  await TTask.Delay(10);
  raise Exception.Create('Intentional fiber observed error');
  Result := 0;
end;

procedure TestUnobservedAsyncProcedure;
var
  InitialCount: Integer;
  I: Integer;
begin
  InitialCount := UnobservedCount;
  FireAndForgetFault();

  { Wait for the background fiber/task to complete and be destroyed }
  for I := 1 to 20 do
    begin
      if UnobservedCount > InitialCount then
        Break;
      Sleep(10);
    end;

  Check('Fire-and-forget fiber procedure triggered OnUnobservedTaskException', UnobservedCount = InitialCount + 1);
  Check('Exception message matched', LastExceptionMsg = 'Intentional fiber fire-and-forget error');
end;

procedure TestObservedExceptionNotTriggered;
var
  InitialCount: Integer;
  F: specialize IFuture<Integer>;
  Caught: Boolean;
  I: Integer;
begin
  InitialCount := UnobservedCount;
  F := AwaitedFault();
  Caught := False;
  try
    F.Value;
  except
    Caught := True;
  end;

  { Release reference so future is destroyed }
  F := nil;
  for I := 1 to 10 do
    Sleep(10);

  Check('Observed exception was caught by caller', Caught);
  Check('Observed exception did not trigger OnUnobservedTaskException', UnobservedCount = InitialCount);
end;

procedure TriggerTaskRun;
begin
  TTask.Run(
    procedure
    begin
      raise Exception.Create('TTask.Run unobserved fiber error');
    end);
end;

procedure TestFireAndForgetTaskRun;
var
  InitialCount: Integer;
  I: Integer;
begin
  InitialCount := UnobservedCount;
  TriggerTaskRun();

  for I := 1 to 20 do
    begin
      if UnobservedCount > InitialCount then
        Break;
      Sleep(10);
    end;

  Check('TTask.Run fire-and-forget triggered OnUnobservedTaskException', UnobservedCount = InitialCount + 1);
  Check('Exception message matched for TTask.Run', LastExceptionMsg = 'TTask.Run unobserved fiber error');
end;

begin
  Passed := 0;
  Failed := 0;
  Writeln('=== Testing OnUnobservedTaskException (FIBER mode) ===');

  OnUnobservedTaskException := @GlobalUnobservedHandler;

  TestUnobservedAsyncProcedure();
  TestObservedExceptionNotTriggered();
  TestFireAndForgetTaskRun();

  Writeln('======================================================');
  Writeln(Format('%d passed, %d failed', [Passed, Failed]));
  if Failed > 0 then
    Halt(1);
end.
