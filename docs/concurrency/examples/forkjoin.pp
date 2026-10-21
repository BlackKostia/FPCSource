{ Fine-grained tasks with System.Threading.ForkJoin: a group of a million
  tasks, a parallel loop and a recursive fork-join.
  See docs/concurrency/guides/forkjoin.md }
program forkjoin;

{$mode objfpc}{$H+}
{$modeswitch arrowfunctions}
{$modeswitch inlinevars}
{$modeswitch interpolation}
{$modeswitch using}

uses
  {$ifdef unix}cthreads,{$endif}
  SysUtils, System.Threading.ForkJoin;

const
  TASKS = 1000000;
  N = 1000000;

var
  Squares: array of Int64;

// Sum of A[aLow..aHigh]: halves run in parallel down to 10 000 elements
function ParallelSum(aLow, aHigh: Int64): Int64;
begin
  if aHigh - aLow < 10000 then
  begin
    Result := 0;
    for var I := aLow to aHigh do
      Inc(Result, Squares[I]);
    Exit;
  end;
  var Mid := (aLow + aHigh) div 2;
  var Left, Right: Int64;
  TForkJoin.Join(() => Left := ParallelSum(aLow, Mid),
                 () => Right := ParallelSum(Mid + 1, aHigh));
  Result := Left + Right;
end;

begin
  WriteLn($'Workers: {TForkJoin.WorkerCount}');

  // 1. A million tasks in one group. The argument is passed by value: the
  //    lambda does not capture the loop variable.
  var Total: Int64 := 0;
  var T0 := GetTickCount64;
  using var Group := TTaskGroup.Create do
  begin
    for var I := 1 to TASKS do
      Group.Spawn(I, Id => InterlockedExchangeAdd64(Total, Id and 1));
    Group.Wait;
  end;
  WriteLn($'Group:  {TASKS} tasks, {Total} odd ids, {GetTickCount64 - T0} ms');

  // 2. A parallel loop: the range is split in halves, not into N tasks
  SetLength(Squares, N);
  T0 := GetTickCount64;
  TForkJoin.Each(0, N - 1, I => Squares[I] := I * I);
  WriteLn($'Each:   {N} squares, {GetTickCount64 - T0} ms');

  // 3. Recursive fork-join
  T0 := GetTickCount64;
  var Sum := ParallelSum(0, N - 1);
  WriteLn($'Join:   sum of squares {Sum}, {GetTickCount64 - T0} ms');

  // 4. The first exception of a task is raised by Wait
  try
    TForkJoin.Each(1, 1000, I =>
      begin
        if I = 500 then
          raise Exception.Create('index 500');
      end);
  except
    on E: Exception do
      WriteLn($'Caught: {E.Message}');
  end;
end.
