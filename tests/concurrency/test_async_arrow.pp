program test_async_arrow;

{ async () => is a separate prefix, like C#. The arrow then follows the
  same state-machine path as a named async routine. A plain () => does not. }

{$mode objfpc}{$H+}
{$modeswitch arrowfunctions}
{$ASYNCMODE STATEMACHINE}

uses
  {$ifdef unix}cthreads,{$endif}
  SysUtils, System.Threading;

type
  TMakeInt = reference to function: specialize IFuture<Integer>;
  TMakeFrom = reference to function(N: Integer): specialize IFuture<Integer>;
  TIntFn = reference to function(X: Integer): Integer;
  TZero = reference to function: Integer;

var
  Passed, Failed: Integer;

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

function Ready: specialize IFuture<Integer>;
var
  Src: specialize TTaskCompletionSource<Integer>;
begin
  Src := specialize TTaskCompletionSource<Integer>.Create;
  Src.SetResultHere(9);
  Result := Src.Task;
  Src.Free;
end;

{ A call whose name is Async must stay a call, even when an argument is an arrow. }
function Async(const F: TIntFn): Integer;
begin
  Result := F(4);
end;

var
  Make: TMakeInt;
  From: TMakeFrom;
  Bare: TMakeFrom;
  F: specialize IFuture<Integer>;
  Sq: TIntFn;
  Zero: TZero;
  T0, Took: QWord;
begin
  Passed := 0;
  Failed := 0;

  Writeln('--- async () => block returns before the delay ---');
  Make := async () =>
    begin
      await TTask.Delay(200);
      Result := 42;
    end;
  T0 := GetTickCount64;
  F := Make();
  Took := GetTickCount64 - T0;
  Check('call returns in under 50ms', Took < 50);
  Check('future is not complete yet', F.Status <> TTaskStatus.Completed);
  Check('block result is 42', F.Value = 42);

  Writeln('--- async (N: Integer) => ---');
  From := async (N: Integer) =>
    begin
      await TTask.Delay(30);
      Result := N + 1;
    end;
  Check('typed parameter yields 8', From(7).Value = 8);

  Writeln('--- async N => ---');
  Bare := async N =>
    begin
      await TTask.Delay(20);
      Result := N + 5;
    end;
  Check('bare parameter yields 11', Bare(6).Value = 11);

  Writeln('--- expression body awaits a completed future ---');
  Make := async () => await Ready;
  T0 := GetTickCount64;
  F := Make();
  Took := GetTickCount64 - T0;
  Check('completed await yields 9', F.Value = 9);
  Check('completed await does not delay', Took < 50);

  Writeln('--- a plain arrow is unchanged ---');
  Sq := (X) => X * X;
  Check('plain arrow squares', Sq(6) = 36);
  Zero := () => 100;
  Check('plain empty arrow', Zero() = 100);

  Writeln('--- Async(...) is a call, not an async arrow ---');
  Check('named Async receives an arrow', Async(X => X + 1) = 5);

  Writeln(Passed, ' passed, ', Failed, ' failed');
  if Failed <> 0 then
    Halt(1);
end.
