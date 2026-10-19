program server_pascal_classic;
{$mode objfpc}{$H+}

uses
  {$ifdef unix}cthreads, baseunix, sockets,{$endif}
  SysUtils, Classes, fgl, syncobjs;

const
  PORT = 9003;
  BACKLOG = 8192;

type
  TStringMap = specialize TFPGMap<string, string>;

  TClientThread = class(TThread)
  private
    FClientFD: cint;
    procedure HandleRequest;
  protected
    procedure Execute; override;
  public
    constructor Create(AClientFD: cint);
  end;

var
  Cache: TStringMap;
  CacheLock: TCriticalSection; { Classic mutex: readers and writers block each other }
  TotalRequests: Int64 = 0;
  TotalReads: Int64 = 0;
  TotalWrites: Int64 = 0;
  TotalComputes: Int64 = 0;
  StartTime: QWord;
  ServerRunning: Boolean = True;

constructor TClientThread.Create(AClientFD: cint);
begin
  FClientFD := AClientFD;
  FreeOnTerminate := True;
  inherited Create(False);
end;

procedure TClientThread.Execute;
begin
  HandleRequest;
end;

function ComputeWork(N: Integer): Int64;
var
  I: Integer;
  S: Int64;
begin
  S := 0;
  for I := 0 to N - 1 do
    S := S xor ((Int64(I) * 37) and $FFFFFFFF);
  Result := S;
end;

function ExtractParam(const Query, Name: string): string;
var
  P, EndP: Integer;
  Prefix: string;
begin
  Result := '';
  Prefix := Name + '=';
  P := Pos(Prefix, Query);
  if P > 0 then
  begin
    Inc(P, Length(Prefix));
    EndP := Pos('&', Copy(Query, P, Length(Query)));
    if EndP > 0 then
      Result := Copy(Query, P, EndP - 1)
    else
      Result := Copy(Query, P, Length(Query));
  end;
end;

procedure TClientThread.HandleRequest;
var
  Buffer: array[0..4095] of AnsiChar;
  BytesRead: ssize_t;
  ReqStr, Line, Method, FullPath, Path, QueryStr: string;
  SpacePos, QPos, StatusCode: Integer;
  StatusText, ResponseBody, Headers, RespStr: string;
  Key, Val: string;
  N, WorkRes: Int64;
  UptimeSec: Double;
  Idx: Integer;
begin
  try
    BytesRead := fprecv(FClientFD, @Buffer[0], SizeOf(Buffer) - 1, 0);
    if BytesRead <= 0 then
      Exit;
    Buffer[BytesRead] := #0;
    ReqStr := PAnsiChar(@Buffer[0]);

    SpacePos := Pos(#13#10, ReqStr);
    if SpacePos > 0 then
      Line := Copy(ReqStr, 1, SpacePos - 1)
    else
      Line := ReqStr;

    SpacePos := Pos(' ', Line);
    if SpacePos <= 0 then
      Exit;

    Method := Copy(Line, 1, SpacePos - 1);
    Delete(Line, 1, SpacePos);
    SpacePos := Pos(' ', Line);
    if SpacePos > 0 then
      FullPath := Copy(Line, 1, SpacePos - 1)
    else
      FullPath := Line;

    QPos := Pos('?', FullPath);
    if QPos > 0 then
    begin
      Path := Copy(FullPath, 1, QPos - 1);
      QueryStr := Copy(FullPath, QPos + 1, Length(FullPath));
    end
    else
    begin
      Path := FullPath;
      QueryStr := '';
    end;

    StatusCode := 200;
    StatusText := 'OK';

    if Path = '/stats' then
    begin
      UptimeSec := (GetTickCount64 - StartTime) / 1000.0;
      CacheLock.Acquire;
      try
        ResponseBody := Format(
          '{"server":"Classic Pascal (Thread-Per-Conn, TCriticalSection, Synchronous)",' +
          '"uptime_s":%.2f,"total_requests":%d,"reads":%d,"writes":%d,"computes":%d,"cache_size":%d}',
          [UptimeSec, TotalRequests, TotalReads, TotalWrites, TotalComputes, Cache.Count]);
      finally
        CacheLock.Release;
      end;
    end
    else if Path = '/get' then
    begin
      Key := ExtractParam(QueryStr, 'key');
      Val := '';
      { In classic Pascal, TCriticalSection blocks even concurrent readers }
      CacheLock.Acquire;
      try
        Idx := Cache.IndexOf(Key);
        if Idx >= 0 then
          Val := Cache.Data[Idx];
      finally
        CacheLock.Release;
      end;
      InterlockedIncrement64(TotalRequests);
      InterlockedIncrement64(TotalReads);
      if Val <> '' then
        ResponseBody := Format('{"key":"%s","val":"%s","found":true}', [Key, Val])
      else
        ResponseBody := Format('{"key":"%s","val":null,"found":false}', [Key]);
    end
    else if Path = '/set' then
    begin
      Key := ExtractParam(QueryStr, 'key');
      Val := ExtractParam(QueryStr, 'val');
      CacheLock.Acquire;
      try
        Idx := Cache.IndexOf(Key);
        if Idx >= 0 then
          Cache.Data[Idx] := Val
        else
          Cache.Add(Key, Val);
      finally
        CacheLock.Release;
      end;
      InterlockedIncrement64(TotalRequests);
      InterlockedIncrement64(TotalWrites);
      ResponseBody := Format('{"key":"%s","val":"%s","status":"stored"}', [Key, Val]);
    end
    else if Path = '/work' then
    begin
      N := StrToIntDef(ExtractParam(QueryStr, 'n'), 1000);
      WorkRes := ComputeWork(N);
      InterlockedIncrement64(TotalRequests);
      InterlockedIncrement64(TotalComputes);
      ResponseBody := Format('{"work_n":%d,"result":%d}', [N, WorkRes]);
    end
    else
    begin
      StatusCode := 404;
      StatusText := 'Not Found';
      ResponseBody := '{"error":"Not Found"}';
    end;

    Headers := Format(
      'HTTP/1.1 %d %s'#13#10 +
      'Content-Type: application/json'#13#10 +
      'Content-Length: %d'#13#10 +
      'Connection: close'#13#10#13#10,
      [StatusCode, StatusText, Length(ResponseBody)]);
    RespStr := Headers + ResponseBody;

    fpsend(FClientFD, PAnsiChar(RespStr), Length(RespStr), 0);
  finally
    CloseSocket(FClientFD);
  end;
end;

var
  ServerFD, ClientFD: cint;
  ServerAddr, ClientAddr: TInetSockAddr;
  AddrLen: TSockLen;
  OptVal: cint;
begin
  Cache := TStringMap.Create;
  Cache.Sorted := True;
  CacheLock := TCriticalSection.Create;
  StartTime := GetTickCount64;

  ServerFD := fpsocket(AF_INET, SOCK_STREAM, 0);
  if ServerFD < 0 then
  begin
    Writeln('Failed to create socket');
    Halt(1);
  end;

  OptVal := 1;
  fpsetsockopt(ServerFD, SOL_SOCKET, SO_REUSEADDR, @OptVal, SizeOf(OptVal));
  fpsetsockopt(ServerFD, SOL_SOCKET, 15, @OptVal, SizeOf(OptVal)); { SO_REUSEPORT }

  FillChar(ServerAddr, SizeOf(ServerAddr), 0);
  ServerAddr.sin_family := AF_INET;
  ServerAddr.sin_port := htons(PORT);
  ServerAddr.sin_addr.s_addr := 0;

  if fpbind(ServerFD, @ServerAddr, SizeOf(ServerAddr)) < 0 then
  begin
    Writeln('Failed to bind to port ', PORT);
    Halt(1);
  end;

  if fplisten(ServerFD, BACKLOG) < 0 then
  begin
    Writeln('Failed to listen on socket');
    Halt(1);
  end;

  Writeln('Classic Free Pascal server listening on port ', PORT, '...');

  while ServerRunning do
  begin
    AddrLen := SizeOf(ClientAddr);
    ClientFD := fpaccept(ServerFD, @ClientAddr, @AddrLen);
    if ClientFD >= 0 then
      TClientThread.Create(ClientFD);
  end;

  CloseSocket(ServerFD);
  CacheLock.Free;
  Cache.Free;
end.

