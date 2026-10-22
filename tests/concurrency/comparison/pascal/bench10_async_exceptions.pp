program bench10_async_exceptions;
{$mode objfpc}{$H+}
{$modeswitch anonymousfunctions}
{$modeswitch arrowfunctions}
{$modeswitch implicitgenerics}

uses
  {$ifdef unix}cthreads,{$endif}
  SysUtils, System.Threading, fclasync;

function Level3Async: specialize IFuture<Integer>; async;
begin
  Result := specialize RunAsync<Integer>(
    function: Integer
    begin
      Sleep(20);
      raise EInOutError.Create('Deep I/O failure at Level 3');
      Result := 42;
    end);
end;

function Level2Async: specialize IFuture<Integer>; async;
begin
  Result := specialize RunAsync<Integer>(
    function: Integer
    var
      V: Integer;
    begin
      V := Level3Async.Value;
      Result := V + 1;
    end);
end;

function Level1Async: specialize IFuture<Integer>; async;
begin
  Result := specialize RunAsync<Integer>(
    function: Integer
    var
      V: Integer;
    begin
      V := Level2Async.Value;
      Result := V + 1;
    end);
end;

var
  Caught: Boolean = False;
  ErrMsg: string = '';
  T0, Took: QWord;
begin
  Writeln('=== Benchmark 10: Deep Async Exception Propagation ===');
  T0 := GetTickCount64;

  try
    Level1Async.Wait;
  except
    on E: EAggregateException do
    begin
      Caught := True;
      if E.Count > 0 then
        ErrMsg := E.InnerExceptions[0].Message
      else
        ErrMsg := E.Message;
    end;
    on E: Exception do
    begin
      Caught := True;
      ErrMsg := E.Message;
    end;
  end;

  Took := GetTickCount64 - T0;

  Writeln('Exception propagated across 3 async levels in: ', Took, ' ms');
  Writeln('Caught message: "', ErrMsg, '"');

  if Caught and (Pos('Deep I/O failure at Level 3', ErrMsg) > 0) then
    Writeln('BENCHMARK 10 PASSED')
  else
    Halt(1);
end.

