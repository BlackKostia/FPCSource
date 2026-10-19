program bench05_continuations;
{$mode objfpc}{$H+}
{$modeswitch anonymousfunctions}
{$modeswitch arrowfunctions}
{$modeswitch implicitgenerics}

uses
  {$ifdef unix}cthreads,{$endif}
  SysUtils, System.Threading;

var
  F0: specialize IFuture<Integer>;
  F1: specialize IFuture<string>;
  F2: specialize IFuture<Integer>;
  T0, Took: QWord;
  FinalResult: Integer;
begin
  Writeln('=== Benchmark 5: Non-blocking Continuations Chaining (ThenBy) ===');
  T0 := GetTickCount64;

  { Pipeline:
      Step 1: Compute integer 21 (takes 30ms)
      Step 2: Transform to string 'Result: 42' (takes 20ms)
      Step 3: Parse and add 8 -> 50
  }
  F0 := TTask.Future(
    function: Integer
    begin
      Sleep(30);
      Result := 21;
    end);

  F1 := F0.ThenBy(
    function(const Prev: ITask): string
    var
      Val: Integer;
    begin
      Val := specialize IFuture<Integer>(Prev).Value;
      Sleep(20);
      Result := 'Result: ' + IntToStr(Val * 2);
    end);

  F2 := F1.ThenBy(
    function(const Prev: ITask): Integer
    var
      S: string;
      Num: Integer;
    begin
      S := specialize IFuture<string>(Prev).Value;
      Num := StrToInt(Copy(S, 9, Length(S) - 8));
      Result := Num + 8;
    end);

  FinalResult := F2.Value;
  Took := GetTickCount64 - T0;

  Writeln('Chained pipeline computed: ', FinalResult, ' in ', Took, ' ms');
  if (FinalResult = 50) and (Took >= 45) then
    Writeln('BENCHMARK 5 PASSED')
  else
    Halt(1);
end.

