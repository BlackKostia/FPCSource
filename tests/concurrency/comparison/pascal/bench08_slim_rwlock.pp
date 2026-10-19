program bench08_slim_rwlock;
{$mode objfpc}{$H+}
{$modeswitch anonymousfunctions}

uses
  {$ifdef unix}cthreads,{$endif}
  SysUtils, SyncObjs, System.Threading;

const
  ReadOpsPerThread = 100000;
  WriteOpsPerThread = 10000;

var
  Lock: TSlimReaderWriterLock;
  SharedCounter: Int64 = 0;
  Tasks: array of ITask;
  T0, Took: QWord;
  I: Integer;
begin
  Writeln('=== Benchmark 8: TSlimReaderWriterLock High Contention ===');
  Lock := TSlimReaderWriterLock.Create;
  T0 := GetTickCount64;

  SetLength(Tasks, 6);

  { 4 Readers }
  for I := 0 to 3 do
  begin
    Tasks[I] := TTask.Run(
      procedure
      var
        J: Integer;
        V: Int64;
      begin
        for J := 1 to ReadOpsPerThread do
        begin
          Lock.BeginRead;
          try
            V := SharedCounter;
          finally
            Lock.EndRead;
          end;
        end;
      end);
  end;

  { 2 Writers }
  for I := 4 to 5 do
  begin
    Tasks[I] := TTask.Run(
      procedure
      var
        J: Integer;
      begin
        for J := 1 to WriteOpsPerThread do
        begin
          Lock.BeginWrite;
          try
            Inc(SharedCounter);
          finally
            Lock.EndWrite;
          end;
        end;
      end);
  end;

  TTask.WaitForAll(Tasks);
  Took := GetTickCount64 - T0;

  Writeln('Completed 400,000 reads + 20,000 writes in: ', Took, ' ms');
  Writeln('Final SharedCounter: ', SharedCounter, ' (Expected: 20000)');

  Lock.Free;

  if (SharedCounter = 20000) then
    Writeln('BENCHMARK 8 PASSED')
  else
    Halt(1);
end.

