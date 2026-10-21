program stress15;

{ 15 await stress tests, paired with csharp/stress/Stress15.cs.
  A line is: number, name, await count, milliseconds, checksum, expected, PASS or FAIL.
  The await count is how many await expressions ran inside the timed section. }

{$mode objfpc}{$H+}
{$modeswitch functionreferences}
{$modeswitch anonymousfunctions}
{$ASYNCMODE STATEMACHINE}

uses
  {$ifdef unix}cthreads,{$endif}
  SysUtils, System.Diagnostics, System.Threading;

type
  TFut = specialize IFuture<Integer>;

const
  ChainN     = 100000;
  CallsN     = 3000;
  YieldN     = 250;
  SeqN       = 20;
  SeqMs      = 15;
  ConcN      = 1000;
  ConcMs     = 40;
  FanN       = 1000;
  FanMs      = 70;
  NestD      = 6;
  NestR      = 150;
  FinallyN   = 4000;
  ExceptN    = 250;
  StrN       = 150;
  ContN      = 30000;
  BreakAtN   = 400;
  BreakTop   = 200000;
  ExitAtN    = 60;
  ExitTop    = 20000;
  ChildN     = 200;
  ChildMs    = 25;
  HammerN    = 300;
  HammerSteps = 4;

var
  Passed, Failed: Integer;
  FinallyCount: Integer;
  Done: specialize IFuture<Integer>;
  Shared: ITask;
  Faults: array of specialize IFuture<Integer>;

procedure Report(const Id, Name: string; Awaits: Integer; const Sw: TStopwatch; Got, Expect: Int64);
var
  Ms: Double;
  St: string;
begin
  Ms := Double(Sw.ElapsedTicks) * 1000.0 / Double(TStopwatch.Frequency);
  if Got = Expect then
    begin
      Inc(Passed);
      St := 'PASS';
    end
  else
    begin
      Inc(Failed);
      St := 'FAIL';
    end;
  Writeln(Id, #9, Name, #9, Awaits, #9, Format('%.2f', [Ms]), #9, Got, #9, Expect, #9, St);
  Flush(Output);
end;

procedure BeginTest(const Id, Name: string);
begin
  Writeln(ErrOutput, '>> ', Id, ' ', Name);
  Flush(ErrOutput);
end;

function ReadyInt(N: Integer): specialize IFuture<Integer>;
var
  Src: specialize TTaskCompletionSource<Integer>;
begin
  Src := specialize TTaskCompletionSource<Integer>.Create;
  Src.SetResult(N);
  while Src.Task.Status <> TTaskStatus.Completed do
    Sleep(1);
  Result := Src.Task;
  Src.Free;
end;

{ Completes on a pool thread. The await usually suspends, then resumes there. }
function Yield1: specialize IFuture<Integer>;
var
  Src: specialize TTaskCompletionSource<Integer>;
begin
  Src := specialize TTaskCompletionSource<Integer>.Create;
  Result := Src.Task;
  TTask.Run(
    procedure
    begin
      Src.SetResult(1);
      Src.Free;
    end);
end;

function Chain: specialize IFuture<Integer>; async;
var
  I, V, S: Integer;
begin
  S := 0;
  for I := 1 to ChainN do
    begin
      V := await Done;
      S := S + V;
    end;
  Result := S;
end;

function Once: specialize IFuture<Integer>; async;
begin
  Result := await Done;
end;

function YieldChain: specialize IFuture<Integer>; async;
var
  I, V, S: Integer;
begin
  S := 0;
  for I := 1 to YieldN do
    begin
      V := await Yield1;
      S := S + V;
    end;
  Result := S;
end;

function SeqDelay: specialize IFuture<Integer>; async;
var
  I: Integer;
begin
  for I := 1 to SeqN do
    await TTask.Delay(SeqMs);
  Result := SeqN;
end;

function ConcOne: specialize IFuture<Integer>; async;
begin
  await TTask.Delay(ConcMs);
  Result := 1;
end;

function FanOne: specialize IFuture<Integer>; async;
begin
  await Shared;
  Result := 1;
end;

function Depth(N: Integer): specialize IFuture<Integer>; async;
var
  V: Integer;
begin
  if N = 0 then
    Result := await Done
  else
    begin
      V := await Depth(N - 1);
      Result := V;
    end;
end;

function FinallyLoop: specialize IFuture<Integer>; async;
var
  I: Integer;
begin
  for I := 1 to FinallyN do
    try
      await Done;
    finally
      Inc(FinallyCount);
    end;
  Result := FinallyCount;
end;

function CatchLoop: specialize IFuture<Integer>; async;
var
  I, S: Integer;
begin
  S := 0;
  for I := 0 to ExceptN - 1 do
    try
      await Faults[I];
    except
      Inc(S);
    end;
  Result := S;
end;

function Grow: specialize IFuture<Integer>; async;
var
  S: string;
  I: Integer;
begin
  S := '';
  for I := 1 to StrN do
    begin
      await Yield1;
      S := S + 'x';
    end;
  Result := Length(S);
end;

function ContinueSum: specialize IFuture<Int64>; async;
var
  I: Integer;
  S: Int64;
begin
  S := 0;
  for I := 1 to ContN do
    begin
      if I mod 3 = 0 then
        Continue;
      await Done;
      S := S + I;
    end;
  Result := S;
end;

function BreakEarly: specialize IFuture<Integer>; async;
var
  I, S: Integer;
begin
  S := 0;
  for I := 1 to BreakTop do
    begin
      await Done;
      S := I;
      if I = BreakAtN then
        Break;
    end;
  Result := S;
end;

function ExitEarly: specialize IFuture<Integer>; async;
var
  I: Integer;
begin
  for I := 1 to ExitTop do
    begin
      await Done;
      if I = ExitAtN then
        begin
          Result := I;
          Exit;
        end;
    end;
  Result := -1;
end;

function Child(N: Integer): specialize IFuture<Integer>; async;
begin
  await TTask.Delay(ChildMs);
  Result := N;
end;

function Parent: specialize IFuture<Integer>; async;
var
  Kids: array of specialize IFuture<Integer>;
  I, V, S: Integer;
begin
  SetLength(Kids, ChildN);
  for I := 0 to ChildN - 1 do
    Kids[I] := Child(I + 1);
  S := 0;
  for I := 0 to ChildN - 1 do
    begin
      V := await Kids[I];
      S := S + V;
    end;
  Result := S;
end;

function Hammer: specialize IFuture<Integer>; async;
var
  I, V, S: Integer;
begin
  S := 0;
  for I := 1 to HammerSteps do
    begin
      V := await Yield1;
      S := S + V;
    end;
  Result := S;
end;

function ExpectedContinue: Int64;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to ContN do
    if I mod 3 <> 0 then
      Result := Result + I;
end;

procedure PrepareFaults;
var
  I: Integer;
  Src: specialize TTaskCompletionSource<Integer>;
begin
  SetLength(Faults, ExceptN);
  for I := 0 to ExceptN - 1 do
    begin
      Src := specialize TTaskCompletionSource<Integer>.Create;
      Src.SetException(Exception.Create('x'));
      while not (Src.Task.Status in [TTaskStatus.Exception, TTaskStatus.Completed, TTaskStatus.Canceled]) do
        Sleep(1);
      Faults[I] := Src.Task;
      Src.Free;
    end;
end;

function SumTasks(const Futs: array of TFut): Int64;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(Futs) do
    Result := Result + Futs[I].Value;
end;

var
  Sw: TStopwatch;
  F: specialize IFuture<Integer>;
  F64: specialize IFuture<Int64>;
  Futs: array of specialize IFuture<Integer>;
  Tasks: array of ITask;
  I: Integer;
  Got: Int64;
  Warm: Integer;
begin
  Passed := 0;
  Failed := 0;
  Done := ReadyInt(1);
  PrepareFaults;
  Warm := Once.Value;
  if Warm <> 1 then
    Halt(2);
  TTask.Delay(1);
  Writeln('# sm-stress pascal');
  Writeln('# threads=', CPUCount, ' freq=', TStopwatch.Frequency);
  Flush(Output);

  BeginTest('01', 'chain_completed');
  Sw := TStopwatch.StartNew;
  F := Chain;
  Got := F.Value;
  Sw.Stop;
  Report('01', 'chain_completed', ChainN, Sw, Got, ChainN);

  BeginTest('02', 'calls_completed');
  Sw := TStopwatch.StartNew;
  Got := 0;
  for I := 1 to CallsN do
    Got := Got + Once.Value;
  Sw.Stop;
  Report('02', 'calls_completed', CallsN, Sw, Got, CallsN);

  BeginTest('03', 'yield_sequential');
  Sw := TStopwatch.StartNew;
  F := YieldChain;
  Got := F.Value;
  Sw.Stop;
  Report('03', 'yield_sequential', YieldN, Sw, Got, YieldN);

  BeginTest('04', 'delay_sequential');
  Sw := TStopwatch.StartNew;
  F := SeqDelay;
  Got := F.Value;
  Sw.Stop;
  Report('04', 'delay_sequential', SeqN, Sw, Got, SeqN);

  BeginTest('05', 'delay_concurrent');
  SetLength(Futs, ConcN);
  SetLength(Tasks, ConcN);
  Sw := TStopwatch.StartNew;
  for I := 0 to ConcN - 1 do
    begin
      Futs[I] := ConcOne;
      Tasks[I] := Futs[I];
    end;
  if not TTask.WaitForAll(Tasks) then
    Got := -1
  else
    Got := SumTasks(Futs);
  Sw.Stop;
  Report('05', 'delay_concurrent', ConcN, Sw, Got, ConcN);

  BeginTest('06', 'fanout_one_delay');
  SetLength(Futs, FanN);
  SetLength(Tasks, FanN);
  Sw := TStopwatch.StartNew;
  Shared := TTask.Delay(FanMs);
  for I := 0 to FanN - 1 do
    begin
      Futs[I] := FanOne;
      Tasks[I] := Futs[I];
    end;
  if not TTask.WaitForAll(Tasks) then
    Got := -1
  else
    Got := SumTasks(Futs);
  Sw.Stop;
  Report('06', 'fanout_one_delay', FanN, Sw, Got, FanN);

  BeginTest('07', 'nested_calls');
  Sw := TStopwatch.StartNew;
  Got := 0;
  for I := 1 to NestR do
    Got := Got + Depth(NestD).Value;
  Sw.Stop;
  Report('07', 'nested_calls', NestR * NestD, Sw, Got, NestR);

  BeginTest('08', 'finally_loop');
  FinallyCount := 0;
  Sw := TStopwatch.StartNew;
  F := FinallyLoop;
  Got := F.Value;
  Sw.Stop;
  Report('08', 'finally_loop', FinallyN, Sw, Got, FinallyN);

  BeginTest('09', 'faulted_loop');
  Sw := TStopwatch.StartNew;
  F := CatchLoop;
  Got := F.Value;
  Sw.Stop;
  Report('09', 'faulted_loop', ExceptN, Sw, Got, ExceptN);

  BeginTest('10', 'string_across_yield');
  Sw := TStopwatch.StartNew;
  F := Grow;
  Got := F.Value;
  Sw.Stop;
  Report('10', 'string_across_yield', StrN, Sw, Got, StrN);

  BeginTest('11', 'continue_loop');
  Sw := TStopwatch.StartNew;
  F64 := ContinueSum;
  Got := F64.Value;
  Sw.Stop;
  Report('11', 'continue_loop', ContN - (ContN div 3), Sw, Got, ExpectedContinue);

  BeginTest('12', 'break_early');
  Sw := TStopwatch.StartNew;
  F := BreakEarly;
  Got := F.Value;
  Sw.Stop;
  Report('12', 'break_early', BreakAtN, Sw, Got, BreakAtN);

  BeginTest('13', 'exit_early');
  Sw := TStopwatch.StartNew;
  F := ExitEarly;
  Got := F.Value;
  Sw.Stop;
  Report('13', 'exit_early', ExitAtN, Sw, Got, ExitAtN);

  BeginTest('14', 'parent_awaits_children');
  Sw := TStopwatch.StartNew;
  F := Parent;
  Got := F.Value;
  Sw.Stop;
  Report('14', 'parent_awaits_children', ChildN * 2, Sw, Got, Int64(ChildN) * (ChildN + 1) div 2);

  BeginTest('15', 'hammer_yield');
  SetLength(Futs, HammerN);
  SetLength(Tasks, HammerN);
  Sw := TStopwatch.StartNew;
  for I := 0 to HammerN - 1 do
    begin
      Futs[I] := Hammer;
      Tasks[I] := Futs[I];
    end;
  if not TTask.WaitForAll(Tasks) then
    Got := -1
  else
    Got := SumTasks(Futs);
  Sw.Stop;
  Report('15', 'hammer_yield', HammerN * HammerSteps, Sw, Got, Int64(HammerN) * HammerSteps);

  Writeln('PASSED ', Passed, '/15');
  if Failed <> 0 then
    Halt(1);
end.
