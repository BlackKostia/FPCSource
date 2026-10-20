{ EXPECT: clean
  threads, classes, strings, dynamic arrays, exceptions and lists without
  memory errors: no reports, no leaks }
program clean_threads;
{$mode objfpc}{$H+}
uses {$ifdef unix}cthreads,{$endif} SysUtils, Classes, SyncObjs;
type
  TWorker = class(TThread)
  protected
    procedure Execute; override;
  public
    Lines: TStringList;
    Id: Integer;
  end;
var
  Lock: TCriticalSection;
  Total: Int64;
procedure TWorker.Execute;
var
  I: Integer;
  A: array of Int64;
  S: AnsiString;
begin
  Lines := TStringList.Create;
  for I := 1 to 2000 do
  begin
    S := Format('%d:%d', [Id, I]);
    Lines.Add(S);
    SetLength(A, I mod 17 + 1);
    A[High(A)] := I;
    try
      if I mod 500 = 0 then
        raise EConvertError.Create(S);
    except
      on E: EConvertError do
        S := E.Message;
    end;
    Lock.Acquire;
    Inc(Total, A[High(A)] + Length(S));
    Lock.Release;
  end;
end;
var
  W: array[0..3] of TWorker;
  I, Count: Integer;
begin
  Lock := TCriticalSection.Create;
  for I := 0 to High(W) do
  begin
    W[I] := TWorker.Create(True);
    W[I].Id := I;
    W[I].Start;
  end;
  Count := 0;
  for I := 0 to High(W) do
  begin
    W[I].WaitFor;
    Inc(Count, W[I].Lines.Count);
    W[I].Lines.Free;
    W[I].Free;
  end;
  Lock.Free;
  WriteLn(Count, ' ', Total);
end.
