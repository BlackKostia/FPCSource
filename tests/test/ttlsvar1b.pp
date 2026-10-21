{ %needlibrary }
{ %target=linux }
{ %delfiles=ttlsvar1a }

{ Threadvars in a library: each thread sees its own copy of the threadvars
  of the library, of a unit compiled with it and of the RTL }
program ttlsvar1b;

{$mode objfpc}

uses
  cthreads, classes, dynlibs;

type
  TIntFunc = function: Integer; cdecl;

  TWorker = class(TThread)
  protected
    procedure Execute; override;
  public
    Ok: Boolean;
  end;

const
  libname = './libttlsvar1a.'+SharedSuffix;

var
  Touch, RaiseAndCatch: TIntFunc;

// Two calls in one thread: 101, then 202; another thread starts again at 101
function CheckThread: Boolean;

begin
  Result:=(Touch()=101) and (Touch()=202) and (RaiseAndCatch()=1);
end;


procedure TWorker.Execute;

begin
  Ok:=CheckThread;
end;


var
  lLib: TLibHandle;
  lWorkers: array[0..3] of TWorker;
  I: Integer;

begin
  lLib:=LoadLibrary(libname);
  if lLib=NilHandle then
    begin
    Writeln('Could not load ',libname);
    Halt(1);
    end;
  Touch:=TIntFunc(GetProcAddress(lLib,'TouchThreadVars'));
  RaiseAndCatch:=TIntFunc(GetProcAddress(lLib,'RaiseAndCatch'));
  if not Assigned(Touch) or not Assigned(RaiseAndCatch) then
    Halt(2);
  if not CheckThread then
    begin
    Writeln('Main thread: wrong threadvar values');
    Halt(3);
    end;
  for I:=0 to High(lWorkers) do
    lWorkers[I]:=TWorker.Create(False);
  for I:=0 to High(lWorkers) do
    begin
    lWorkers[I].WaitFor;
    if not lWorkers[I].Ok then
      begin
      Writeln('Thread ',I,': wrong threadvar values');
      Halt(4);
      end;
    lWorkers[I].Free;
    end;
  Writeln('ok');
end.
