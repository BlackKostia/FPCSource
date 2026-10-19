program server_pascal;
{$mode objfpc}{$H+}
{$modeswitch advancedrecords}
{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}
{$modeswitch implicitgenerics}

uses
  {$ifdef unix}cthreads, baseunix, sockets,{$endif}
  SysUtils, Classes, fgl, SyncObjs, System.Threading;

const
  PORT = 9002;
  BACKLOG = 8192;

type
  TLogEntry = record
    Timestamp: QWord;
    Method: string;
    Path: string;
    StatusCode: Integer;
  end;

  TStringMap = specialize TFPGMap<string, string>;

var
  Cache: TStringMap;
  CacheLock: TSlimReaderWriterLock;
  LogChannel: specialize TChannel<TLogEntry>;
  ServerRunning: Boolean = True;

  TotalRequests: Int64 = 0;
  TotalReads: Int64 = 0;
  TotalWrites: Int64 = 0;
  TotalComputes: Int64 = 0;
  StartTime: QWord;

procedure RunLogConsumer;
var
  Entry: TLogEntry;
  Count: Int64 = 0;
begin
  for Entry in LogChannel do
  begin
    Inc(Count);
  end;
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

procedure HandleClient(ClientFD: cint);
var
  Buffer: array[0..4095] of AnsiChar;
  BytesRead: ssize_t;
  ReqStr, Line, Method, FullPath, Path, QueryStr: string;
  SpacePos, QPos, StatusCode: Integer;
  StatusText, ResponseBody, Headers, RespStr: string;
  Key, Val: string;
  N, WorkRes: Int64;
  LogItem: TLogEntry;
  UptimeSec: Double;
  Idx: Integer;
begin
  try
    BytesRead := fprecv(ClientFD, @Buffer[0], SizeOf(Buffer) - 1, 0);
    if BytesRead <= 0 then
    begin
      CloseSocket(ClientFD);
      Exit;
    end;
    Buffer[BytesRead] := #0;
    ReqStr := PAnsiChar(@Buffer[0]);

    // Parse HTTP request line
    SpacePos := Pos(#13#10, ReqStr);
    if SpacePos > 0 then
      Line := Copy(ReqStr, 1, SpacePos - 1)
    else
      Line := ReqStr;

    SpacePos := Pos(' ', Line);
    if SpacePos <= 0 then
    begin
      CloseSocket(ClientFD);
      Exit;
    end;

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
      CacheLock.BeginRead;
      try
        ResponseBody := Format(
          '{"server":"ModernFreePascal (Zero-GIL, TSlimRWLock, TChannel, TThreadPool)",' +
          '"uptime_s":%.2f,"total_requests":%d,"reads":%d,"writes":%d,"computes":%d,"cache_size":%d}',
          [UptimeSec, TotalRequests, TotalReads, TotalWrites, TotalComputes, Cache.Count]);
      finally
        CacheLock.EndRead;
      end;
    end
    else if Path = '/get' then
    begin
      Key := ExtractParam(QueryStr, 'key');
      Val := '';
      CacheLock.BeginRead;
      try
        Idx := Cache.IndexOf(Key);
        if Idx >= 0 then
          Val := Cache.Data[Idx];
      finally
        CacheLock.EndRead;
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
      CacheLock.BeginWrite;
      try
        Idx := Cache.IndexOf(Key);
        if Idx >= 0 then
          Cache.Data[Idx] := Val
        else
          Cache.Add(Key, Val);
      finally
        CacheLock.EndWrite;
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

    // Send to background CSP channel (non-blocking TrySend)
    LogItem.Timestamp := GetTickCount64;
    LogItem.Method := Method;
    LogItem.Path := Path;
    LogItem.StatusCode := StatusCode;
    LogChannel.TrySend(LogItem);

    // Build HTTP response
    Headers := Format(
      'HTTP/1.1 %d %s'#13#10 +
      'Content-Type: application/json'#13#10 +
      'Content-Length: %d'#13#10 +
      'Connection: close'#13#10#13#10,
      [StatusCode, StatusText, Length(ResponseBody)]);
    RespStr := Headers + ResponseBody;

    fpsend(ClientFD, PAnsiChar(RespStr), Length(RespStr), 0);
  finally
    CloseSocket(ClientFD);
  end;
end;

procedure DispatchClient(AClientFD: cint);
begin
  TTask.Run(procedure
  begin
    HandleClient(AClientFD);
  end);
end;

var
  ServerFD, ClientFD: cint;
  ServerAddr, ClientAddr: TInetSockAddr;
  AddrLen: TSockLen;
  OptVal: cint;
begin
  Cache := TStringMap.Create;
  Cache.Sorted := True;
  CacheLock := TSlimReaderWriterLock.Create;
  LogChannel := specialize TChannel<TLogEntry>.Create(100000);
  StartTime := GetTickCount64;

  // Configure ThreadPool for high connection concurrency
  TThreadPool.Default.SetMinWorkerThreads(32);
  TThreadPool.Default.SetMaxWorkerThreads(128);

  // Start background logging consumer task
  TTask.Run(@RunLogConsumer);

  ServerFD := fpsocket(AF_INET, SOCK_STREAM, 0);
  if ServerFD < 0 then
  begin
    Writeln('Failed to create socket');
    Halt(1);
  end;

  OptVal := 1;
  fpsetsockopt(ServerFD, SOL_SOCKET, SO_REUSEADDR, @OptVal, SizeOf(OptVal));
  fpsetsockopt(ServerFD, SOL_SOCKET, 15, @OptVal, SizeOf(OptVal)); // SO_REUSEPORT on Linux

  FillChar(ServerAddr, SizeOf(ServerAddr), 0);
  ServerAddr.sin_family := AF_INET;
  ServerAddr.sin_port := htons(PORT);
  ServerAddr.sin_addr.s_addr := 0; // INADDR_ANY

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

  Writeln('Modern Free Pascal multithreaded server listening on port ', PORT, '...');

  while ServerRunning do
  begin
    AddrLen := SizeOf(ClientAddr);
    ClientFD := fpaccept(ServerFD, @ClientAddr, @AddrLen);
    if ClientFD >= 0 then
      DispatchClient(ClientFD);
  end;

  CloseSocket(ServerFD);
  LogChannel.Close;
  CacheLock.Free;
  Cache.Free;
end.
