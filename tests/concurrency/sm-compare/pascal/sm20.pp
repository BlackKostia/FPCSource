program sm20;

{ 20 checks of {$ASYNCMODE STATEMACHINE}, paired with csharp/Sm20.cs.
  A line is: number, name, milliseconds, PASS or FAIL. }

{$mode objfpc}{$H+}
{$modeswitch functionreferences}
{$ASYNCMODE STATEMACHINE}

uses
  {$ifdef unix}cthreads,{$endif}
  SysUtils, System.Threading;

var
  Passed, Failed: Integer;
  FinallyFlag: Integer;
  Done: specialize IFuture<Integer>;
  DoneTask: ITask;

procedure Line(const Id, Name: string; Ms: QWord; Ok: Boolean);
var
  St: string;
begin
  if Ok then
    begin
      Inc(Passed);
      St := 'PASS';
    end
  else
    begin
      Inc(Failed);
      St := 'FAIL';
    end;
  Writeln(Id, #9, Name, #9, Ms, #9, St);
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

function ReadyTask: ITask;
var
  Src: specialize TTaskCompletionSource<Byte>;
begin
  Src := specialize TTaskCompletionSource<Byte>.Create;
  Src.SetResult(0);
  while Src.Task.Status <> TTaskStatus.Completed do
    Sleep(1);
  Result := Src.Task;
  Src.Free;
end;

function SyncOne: specialize IFuture<Integer>; async;
begin
  Result := 1;
end;

function Pipeline: specialize IFuture<Integer>; async;
var
  N: Integer;
begin
  N := 1;
  await TTask.Delay(100);
  N := N + 1;
  await TTask.Delay(100);
  Result := N + 40;
end;

function Take(const A: specialize IFuture<Integer>): specialize IFuture<Integer>; async;
begin
  Result := await A;
end;

function Faulted: specialize IFuture<Integer>; async;
var
  Src: specialize TTaskCompletionSource<Integer>;
begin
  Src := specialize TTaskCompletionSource<Integer>.Create;
  try
    Src.SetException(Exception.Create('boom'));
    Result := await Src.Task;
  finally
    Src.Free;
  end;
end;

function Caught: specialize IFuture<Integer>; async;
var
  Src: specialize TTaskCompletionSource<Integer>;
begin
  Src := specialize TTaskCompletionSource<Integer>.Create;
  try
    Src.SetException(Exception.Create('boom'));
    try
      Result := await Src.Task;
    except
      Result := -1;
    end;
  finally
    Src.Free;
  end;
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
      await Done;
      Result := 1;
    end
  else
    begin
      await Done;
      Result := 2;
    end;
end;

function WhileSum: specialize IFuture<Integer>; async;
var
  I, S, V: Integer;
begin
  I := 1;
  S := 0;
  while I <= 3 do
    begin
      V := await Done;
      S := S + I;
      if V <> 1 then
        S := -100;
      I := I + 1;
    end;
  Result := S;
end;

function ForSum: specialize IFuture<Integer>; async;
var
  I, S: Integer;
begin
  S := 0;
  for I := 1 to 3 do
    begin
      await Done;
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
      await Done;
      if I = 3 then
        Break;
      Result := Result + I;
    end;
end;

function Early: specialize IFuture<Integer>; async;
begin
  await Done;
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
  await TTask.Delay(30);
  Result := S + 'c';
end;

function DownToSum: specialize IFuture<Integer>; async;
var
  I, S: Integer;
begin
  S := 0;
  for I := 3 downto 1 do
    begin
      await Done;
      S := S + I;
    end;
  Result := S;
end;

function ContinueSum: specialize IFuture<Integer>; async;
var
  I, S: Integer;
begin
  S := 0;
  for I := 1 to 5 do
    begin
      if I = 3 then
        Continue;
      await Done;
      S := S + I;
    end;
  Result := S;
end;

function RepeatThree: specialize IFuture<Integer>; async;
var
  I: Integer;
begin
  I := 0;
  repeat
    I := I + 1;
    await Done;
    Continue;
  until I = 3;
  Result := I;
end;

function WaitOnly: ITask; async;
begin
  await DoneTask;
end;

function OneOf(N: Integer): specialize IFuture<Integer>; async;
begin
  await TTask.Delay(30);
  Result := N;
end;

function Chain(const A: specialize IFuture<Integer>): specialize IFuture<Integer>; async;
var
  I, S, V: Integer;
begin
  S := 0;
  for I := 1 to 100 do
    begin
      V := await A;
      S := S + V;
    end;
  Result := S;
end;

function ReadRaises(const F: specialize IFuture<Integer>): Boolean;
begin
  Result := False;
  try
    if F.Value = 0 then
      ;
  except
    Result := True;
  end;
end;

var
  T0, Ms: QWord;
  F: specialize IFuture<Integer>;
  FS: specialize IFuture<string>;
  Tk: ITask;
  Text: string;
  Tasks: array of ITask;
  Futs: array of specialize IFuture<Integer>;
  I, S, Bad: Integer;
  FlagAtReturn: Integer;
begin
  Passed := 0;
  Failed := 0;
  Done := ReadyInt(1);
  DoneTask := ReadyTask;
  Writeln('# sm-compare pascal');

  T0 := GetTickCount64;
  Bad := 0;
  for I := 1 to 2000 do
    if SyncOne.Value <> 1 then
      Inc(Bad);
  Line('01', 'sync_x2000', GetTickCount64 - T0, Bad = 0);

  T0 := GetTickCount64;
  F := Pipeline;
  Ms := GetTickCount64 - T0;
  Line('02', 'call_returns_early', Ms,
    (Ms < 40) and (F.Status <> TTaskStatus.Completed) and (F.Value = 42));

  T0 := GetTickCount64;
  F := Take(ReadyInt(7));
  Ms := GetTickCount64 - T0;
  Line('03', 'await_completed', Ms, (Ms < 40) and (F.Value = 7));

  T0 := GetTickCount64;
  Bad := Ord(ReadRaises(Faulted));
  Line('04', 'faulted_raises', GetTickCount64 - T0, Bad <> 0);

  T0 := GetTickCount64;
  F := Caught;
  S := F.Value;
  Line('05', 'except_sets_minus1', GetTickCount64 - T0, S = -1);

  T0 := GetTickCount64;
  Bad := Ord(ReadRaises(Raises));
  Line('06', 'raise_faults', GetTickCount64 - T0, Bad <> 0);

  T0 := GetTickCount64;
  F := Branch(1);
  S := F.Value;
  Line('07', 'if_then', GetTickCount64 - T0, S = 1);

  T0 := GetTickCount64;
  F := Branch(-1);
  S := F.Value;
  Line('08', 'if_else', GetTickCount64 - T0, S = 2);

  T0 := GetTickCount64;
  F := WhileSum;
  S := F.Value;
  Line('09', 'while_sum', GetTickCount64 - T0, S = 6);

  T0 := GetTickCount64;
  F := ForSum;
  S := F.Value;
  Line('10', 'for_sum', GetTickCount64 - T0, S = 6);

  T0 := GetTickCount64;
  F := BreakAt;
  S := F.Value;
  Line('11', 'break_is_3', GetTickCount64 - T0, S = 3);

  T0 := GetTickCount64;
  F := Early;
  S := F.Value;
  Line('12', 'exit_keeps_5', GetTickCount64 - T0, S = 5);

  FinallyFlag := 0;
  T0 := GetTickCount64;
  F := WithFinally;
  Ms := GetTickCount64 - T0;
  FlagAtReturn := FinallyFlag;
  Line('13', 'finally_after_resume', Ms,
    (Ms < 40) and (FlagAtReturn = 0) and (F.Value = 1) and (FinallyFlag = 1));

  T0 := GetTickCount64;
  FS := Sticky;
  Text := FS.Value;
  Line('14', 'string_abc', GetTickCount64 - T0, Text = 'abc');

  T0 := GetTickCount64;
  F := DownToSum;
  S := F.Value;
  Line('15', 'downto_sum', GetTickCount64 - T0, S = 6);

  T0 := GetTickCount64;
  F := ContinueSum;
  S := F.Value;
  Line('16', 'continue_sum', GetTickCount64 - T0, S = 12);

  T0 := GetTickCount64;
  F := RepeatThree;
  S := F.Value;
  Line('17', 'repeat_is_3', GetTickCount64 - T0, S = 3);

  T0 := GetTickCount64;
  Tk := WaitOnly;
  Tk.Wait;
  Line('18', 'itask_completes', GetTickCount64 - T0, Tk.Status = TTaskStatus.Completed);

  SetLength(Futs, 100);
  SetLength(Tasks, 100);
  T0 := GetTickCount64;
  for I := 0 to 99 do
    begin
      Futs[I] := OneOf(I + 1);
      Tasks[I] := Futs[I];
    end;
  if not TTask.WaitForAll(Tasks) then
    S := -1
  else
    begin
      S := 0;
      for I := 0 to 99 do
        S := S + Futs[I].Value;
    end;
  Ms := GetTickCount64 - T0;
  Line('19', 'concurrent_100x30ms', Ms, (S = 5050) and (Ms >= 20));

  T0 := GetTickCount64;
  F := Chain(Done);
  S := F.Value;
  Line('20', 'chain_100', GetTickCount64 - T0, S = 100);

  Writeln('PASSED ', Passed, '/20');
  if Failed <> 0 then
    Halt(1);
end.
