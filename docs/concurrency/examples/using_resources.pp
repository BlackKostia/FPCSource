{ The resource statement ({$modeswitch using}): "using ... do" frees a
  class instance (or releases a COM interface) at the end of the statement,
  also after an exception or Exit, without try..finally.
  See docs/concurrency/language/using.md }
program using_resources;

{$mode objfpc}{$H+}
{$modeswitch using}

uses
  SysUtils, Classes, fpjson, jsonparser;

{ files and streams: several resources are freed in reverse order }
procedure CopyFile(const Source, Dest: string);
begin
  using var Src := TFileStream.Create(Source, fmOpenRead or fmShareDenyWrite),
        var Dst := TFileStream.Create(Dest, fmCreate) do
    Dst.CopyFrom(Src, 0);
end;

{ a temporary container }
function SortedLines(const FileName: string): string;
begin
  using var Lines := TStringList.Create do
    begin
      Lines.LoadFromFile(FileName);
      Lines.Sort;
      Result := Lines.CommaText;
    end;
end;

{ parsing: the document is only needed for a moment }
function ReadPort(const Config: string): Integer;
begin
  using var Json := GetJSON(Config) do
    Result := TJSONObject(Json).Get('port', 8080);
end;

{ a variable of the var section: it is nil after the statement }
function CountWords(const Text: string): Integer;
var
  Words: TStringList;
begin
  using Words := TStringList.Create do
    begin
      Words.Delimiter := ' ';
      Words.StrictDelimiter := True;
      Words.DelimitedText := Text;
      Result := Words.Count;
    end;
  Assert(Words = nil);
end;

{ an exception in the statement: the resource is freed, the exception
  propagates }
procedure FailInTheMiddle(const FileName: string);
begin
  using var Stream := TFileStream.Create(FileName, fmOpenRead) do
    if Stream.Size > 0 then
      raise Exception.Create('stop after opening ' + ExtractFileName(FileName));
end;

var
  Dir, A, B: string;

begin
  Dir := IncludeTrailingPathDelimiter(GetTempDir(False));
  A := Dir + 'using_a.txt';
  B := Dir + 'using_b.txt';

  using var L := TStringList.Create do
    begin
      L.Add('pear');
      L.Add('apple');
      L.Add('plum');
      L.SaveToFile(A);
    end;

  CopyFile(A, B);
  WriteLn('sorted: ', SortedLines(B));
  WriteLn('port:   ', ReadPort('{"host": "localhost", "port": 9000}'));
  WriteLn('words:  ', CountWords('using frees the resource'));
  try
    FailInTheMiddle(B);
  except
    on E: Exception do
      WriteLn('caught: ', E.Message);
  end;

  DeleteFile(A);
  DeleteFile(B);
end.
