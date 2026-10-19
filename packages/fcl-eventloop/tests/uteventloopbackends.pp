{
    This file is part of the Free Component Library (FCL)
    Copyright (c) 2026 by the Free Pascal development team

    Scalable Asynchronous I/O Event Loop - behaviour tests run against
    every Linux backend (epoll and io_uring)

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.
}
{$mode objfpc}{$H+}
{$modeswitch functionreferences}
{$modeswitch anonymousfunctions}

unit uteventloopbackends;

interface

uses
  SysUtils, Classes, SyncObjs, fpcunit, testregistry, System.Threading,
  {$ifdef UNIX}baseunix,{$endif}
  eventloop.types, eventloop.core, eventloop.sockets, eventloop.pipes, eventloop.files, fcleventloop;

type
  TCondition = reference to function: Boolean;

  { Tests of one backend; the subclasses at the end pick the backend. }
  TBackendTestCase = class(TTestCase)
  protected
    FLoop: IEventLoop;
    FServer: IAsyncServerSocket;
    function Backend: TEventLoopBackendKind; virtual; abstract;
    procedure SetUp; override;
    procedure TearDown; override;
    function PumpUntil(const ACond: TCondition; ATimeoutMs: Integer = 3000): Boolean;
    procedure ConnectPair(out AClient, APeer: IAsyncSocket);
  published
    { Loop core }
    procedure TestRunOnceWaitsForTimeout;
    procedure TestIdleRegisteredHandlesDoNotSpin;
    procedure TestStopBeforeRun;
    procedure TestRunAfterStopAndRun;
    procedure TestHandlerExceptionDoesNotEndRun;
    procedure TestTimersFireInDeadlineOrder;
    procedure TestManyCancelledTimers;
    procedure TestPeriodicZeroInterval;
    { Sockets }
    procedure TestPeerCloseCompletesRead;
    procedure TestIdleSocketAfterPeerCloseDoesNotSpin;
    procedure TestWriteToClosedPeerReportsError;
    procedure TestCloseCompletesPendingRead;
    procedure TestLargeTransfer;
    procedure TestConnectRefusedCallsBack;
    procedure TestHostNameIsRejected;
    procedure TestReadAsyncCancellation;
    procedure TestAcceptAsyncIsOneShot;
    procedure TestAcceptAsyncCanceledByServerClose;
    procedure TestReadAsyncCompletedByClose;
    { Pipes }
    procedure TestPipeEndOfFileAfterWriterClose;
    procedure TestPipeIdleAfterWriterCloseDoesNotSpin;
    procedure TestPipeWriteWithoutReaderReportsEPipe;
    { Files }
    procedure TestFileCreateIsWritable;
    procedure TestFileReleasedWhileOperationPending;
  end;

  TTestEpollBackend = class(TBackendTestCase)
  protected
    function Backend: TEventLoopBackendKind; override;
  end;

  TTestIOUringBackend = class(TBackendTestCase)
  protected
    function Backend: TEventLoopBackendKind; override;
  end;

  { Event loop groups do not depend on the backend. }
  TTestEventLoopGroupLifetime = class(TTestCase)
  published
    procedure TestDestroyWithoutStart;
    procedure TestStartStopWait;
  end;

implementation

{$ifdef UNIX}
uses
  eventloop.backend.uring;
{$endif}

type
  { Runs a procedure in a thread so that a hang shows up as a timeout. }
  TRunThread = class(TThread)
  private
    FProcRef: TAsyncProc;
  protected
    procedure Execute; override;
  public
    constructor Create(const AProc: TAsyncProc);
  end;

constructor TRunThread.Create(const AProc: TAsyncProc);
begin
  FProcRef := AProc;
  FreeOnTerminate := False;
  inherited Create(False);
end;

procedure TRunThread.Execute;
begin
  FProcRef();
end;

function RunsWithin(const AProc: TAsyncProc; ATimeoutMs: Integer): Boolean;
var
  LThread: TRunThread;
  LStart: QWord;
begin
  LThread := TRunThread.Create(AProc);
  LStart := GetTickCount64;
  while not LThread.Finished and (GetTickCount64 - LStart < QWord(ATimeoutMs)) do
    Sleep(5);
  Result := LThread.Finished;
  if Result then
    LThread.Free; { a hung thread is leaked on purpose: freeing it would hang too }
end;

type
  TRaisingHandler = class
  public
    Calls: Integer;
    procedure OnIO(AHandle: TLoopHandle; AEvents: TEventLoopEvents; AUserData: Pointer);
  end;

procedure TRaisingHandler.OnIO(AHandle: TLoopHandle; AEvents: TEventLoopEvents; AUserData: Pointer);
begin
  Inc(Calls);
  raise Exception.Create('handler failure');
end;

type
  { Pipe and file callbacks are methods }
  TPipeReader = class
  public
    Done: Boolean;
    Bytes: NativeInt;
    Status: Integer;
    procedure OnRead(ABytes: NativeInt; AStatus: Integer);
  end;

  TPipeWriter = class
  public
    Done: Boolean;
    Bytes: NativeInt;
    Status: Integer;
    procedure OnWrite(ABytes: NativeInt; AStatus: Integer);
  end;

procedure TPipeReader.OnRead(ABytes: NativeInt; AStatus: Integer);
begin
  Bytes := ABytes;
  Status := AStatus;
  Done := True;
end;

procedure TPipeWriter.OnWrite(ABytes: NativeInt; AStatus: Integer);
begin
  Bytes := ABytes;
  Status := AStatus;
  Done := True;
end;

type
  TTimerLog = class
  public
    Fired: array of Int64;
    procedure OnTimer(ATimerId: Int64);
  end;

procedure TTimerLog.OnTimer(ATimerId: Int64);
begin
  SetLength(Fired, Length(Fired) + 1);
  Fired[High(Fired)] := ATimerId;
end;

{ TBackendTestCase }

procedure TBackendTestCase.SetUp;
begin
  {$ifdef UNIX}
  if (Backend = bkIOUring) and not TIOUringEventLoop.IsSupported then
    Ignore('io_uring is not available on this system');
  {$endif}
  FLoop := TEventLoop.Create(Backend);
end;

procedure TBackendTestCase.TearDown;
begin
  if FServer <> nil then
    FServer.Close;
  FServer := nil;
  FLoop := nil;
end;

function TBackendTestCase.PumpUntil(const ACond: TCondition; ATimeoutMs: Integer): Boolean;
var
  LStart: QWord;
begin
  LStart := GetTickCount64;
  repeat
    if ACond() then
      Exit(True);
    FLoop.RunOnce(10);
  until GetTickCount64 - LStart > QWord(ATimeoutMs);
  Result := ACond();
end;

procedure TBackendTestCase.ConnectPair(out AClient, APeer: IAsyncSocket);
var
  LPeer, LClient: IAsyncSocket;
begin
  LPeer := nil;
  FServer := TEventLoop.CreateTcpServer(FLoop);
  FServer.Listen('127.0.0.1', 0);
  FServer.AsyncAccept(
    procedure(AClientHandle: TLoopHandle; const AClientAddr: string; AClientPort: Word; AStatus: Integer)
    begin
      if AStatus = 0 then
        LPeer := TAsyncSocket.Create(FLoop, AClientHandle, True);
    end);
  LClient := TEventLoop.CreateTcpClient(FLoop);
  LClient.AsyncConnect('127.0.0.1', FServer.Port, nil);
  AssertTrue('Connection established',
    PumpUntil(function: Boolean begin Result := (LPeer <> nil) and LClient.Connected; end));
  AClient := LClient;
  APeer := LPeer;
end;

procedure TBackendTestCase.TestRunOnceWaitsForTimeout;
var
  LStart, LElapsed: QWord;
  LCalls: Integer;
begin
  LStart := GetTickCount64;
  LCalls := 0;
  while GetTickCount64 - LStart < 200 do
  begin
    FLoop.RunOnce(200);
    Inc(LCalls);
  end;
  LElapsed := GetTickCount64 - LStart;
  AssertTrue('RunOnce(200) returned ' + IntToStr(LCalls) + ' times in ' + IntToStr(LElapsed) + ' ms',
    LCalls <= 3);
end;

procedure TBackendTestCase.TestIdleRegisteredHandlesDoNotSpin;
var
  LClient, LPeer: IAsyncSocket;
  LBuf: array[0..15] of Byte;
  LStart: QWord;
  LCalls: Integer;
begin
  ConnectPair(LClient, LPeer);
  { A pending read that gets no data, and a listening server with an
    accept handler but no connection: nothing is ready. }
  LPeer.AsyncRead(@LBuf[0], SizeOf(LBuf), TAsyncReadCallback(nil));
  LClient.AsyncRead(@LBuf[0], SizeOf(LBuf),
    procedure(ABytes: NativeInt; AStatus: Integer) begin end);
  LStart := GetTickCount64;
  LCalls := 0;
  while GetTickCount64 - LStart < 300 do
  begin
    FLoop.RunOnce(100);
    Inc(LCalls);
  end;
  AssertTrue('Loop with idle handles woke ' + IntToStr(LCalls) + ' times in 300 ms', LCalls <= 6);
end;

procedure TBackendTestCase.TestStopBeforeRun;
var
  LLoop: IEventLoop;
begin
  LLoop := FLoop;
  LLoop.Stop;
  AssertTrue('Run returns at once after an earlier Stop',
    RunsWithin(procedure begin LLoop.Run; end, 2000));
end;

procedure TBackendTestCase.TestRunAfterStopAndRun;
var
  LLoop: IEventLoop;
  LTicks: Integer;
begin
  LLoop := FLoop;
  LLoop.Stop;
  LLoop.Run; { consumes the Stop }
  LTicks := 0;
  LLoop.SetTimer(1, TAsyncTimerCallback(nil), False);
  LLoop.Post(procedure begin Inc(LTicks); LLoop.Post(procedure begin Inc(LTicks); LLoop.Stop; end); end);
  AssertTrue('A second Run works normally', RunsWithin(procedure begin LLoop.Run; end, 2000));
  AssertEquals('Both posted procedures ran', 2, LTicks);
end;

procedure TBackendTestCase.TestHandlerExceptionDoesNotEndRun;
var
  LPipe: IAsyncPipe;
  LHandler: TRaisingHandler;
  LByte: Byte;
  LLoop: IEventLoop;
begin
  LHandler := TRaisingHandler.Create;
  try
    LPipe := TEventLoop.CreatePipe(FLoop);
    LByte := 1;
    {$ifdef UNIX}
    fpwrite(LPipe.WriterHandle, LByte, 1);
    {$endif}
    FLoop.RegisterHandle(LPipe.ReaderHandle, [eleRead], @LHandler.OnIO, nil);
    LLoop := FLoop;
    FLoop.SetTimer(100, TAsyncTimerCallback(nil), False);
    FLoop.Post(procedure begin end);
    { Stop from a timer once the handler has raised a few times }
    TThread.CreateAnonymousThread(procedure begin Sleep(150); LLoop.Stop; end).Start;
    AssertTrue('Run survives a raising I/O handler and ends by Stop',
      RunsWithin(procedure begin LLoop.Run; end, 3000));
    AssertTrue('Handler was called', LHandler.Calls > 0);
    FLoop.UnregisterHandle(LPipe.ReaderHandle);
  finally
    LHandler.Free;
  end;
end;

procedure TBackendTestCase.TestTimersFireInDeadlineOrder;
const
  LDelays: array[0..5] of Cardinal = (60, 10, 40, 10, 0, 25);
  LExpected: array[0..5] of Integer = (4, 1, 3, 5, 2, 0);
var
  LLog: TTimerLog;
  LIds: array[0..5] of Int64;
  I: Integer;
begin
  LLog := TTimerLog.Create;
  try
    for I := 0 to High(LDelays) do
      LIds[I] := FLoop.SetTimer(LDelays[I], @LLog.OnTimer, False);
    AssertTrue('All timers fired', PumpUntil(function: Boolean begin Result := Length(LLog.Fired) >= 6; end));
    for I := 0 to High(LExpected) do
      AssertEquals('Timer #' + IntToStr(I) + ' in deadline order (ties by creation)',
        LIds[LExpected[I]], LLog.Fired[I]);
  finally
    LLog.Free;
  end;
end;

procedure TBackendTestCase.TestManyCancelledTimers;
const
  N = 2000;
var
  LLog: TTimerLog;
  LIds: array of Int64;
  I, J: Integer;
begin
  LLog := TTimerLog.Create;
  try
    SetLength(LIds, N);
    for I := 0 to N - 1 do
      LIds[I] := FLoop.SetTimer(5 + Cardinal(I mod 50), @LLog.OnTimer, False);
    { Cancel the odd ones, which makes the heap compact itself }
    for I := 0 to N - 1 do
      if Odd(I) then
        FLoop.CancelTimer(LIds[I]);
    AssertTrue('All remaining timers fired',
      PumpUntil(function: Boolean begin Result := Length(LLog.Fired) >= N div 2; end));
    FLoop.RunOnce(80);
    AssertEquals('Exactly the uncancelled timers fired', N div 2, Length(LLog.Fired));
    for J := 0 to High(LLog.Fired) do
      AssertFalse('A cancelled timer fired', Odd(LLog.Fired[J] - LIds[0]));
  finally
    LLog.Free;
  end;
end;

procedure TBackendTestCase.TestPeriodicZeroInterval;
var
  LLog: TTimerLog;
  LId: Int64;
begin
  LLog := TTimerLog.Create;
  try
    LId := FLoop.SetTimer(0, @LLog.OnTimer, True);
    AssertTrue('RunOnce with a 0 ms periodic timer returns',
      RunsWithin(procedure var K: Integer; begin for K := 1 to 5 do FLoop.RunOnce(5); end, 3000));
    AssertTrue('Periodic timer fired more than once', Length(LLog.Fired) > 1);
    FLoop.CancelTimer(LId);
  finally
    LLog.Free;
  end;
end;

procedure TBackendTestCase.TestPeerCloseCompletesRead;
var
  LClient, LPeer: IAsyncSocket;
  LBuf: array[0..15] of Byte;
  LDone: Boolean;
  LBytes: NativeInt;
begin
  ConnectPair(LClient, LPeer);
  LDone := False;
  LBytes := -2;
  LClient.AsyncRead(@LBuf[0], SizeOf(LBuf),
    procedure(ABytes: NativeInt; AStatus: Integer)
    begin
      LBytes := ABytes;
      LDone := True;
    end);
  LPeer.Close;
  AssertTrue('Pending read completes when the peer closes',
    PumpUntil(function: Boolean begin Result := LDone; end));
  AssertEquals('End of file is reported as 0 bytes', 0, LBytes);
end;

procedure TBackendTestCase.TestIdleSocketAfterPeerCloseDoesNotSpin;
var
  LClient, LPeer: IAsyncSocket;
  LStart: QWord;
  LCalls: Integer;
begin
  ConnectPair(LClient, LPeer);
  LPeer.Close;
  FLoop.RunOnce(20);
  LStart := GetTickCount64;
  LCalls := 0;
  while GetTickCount64 - LStart < 300 do
  begin
    FLoop.RunOnce(100);
    Inc(LCalls);
  end;
  AssertTrue('Idle socket with a closed peer woke the loop ' + IntToStr(LCalls) + ' times', LCalls <= 6);
end;

procedure TBackendTestCase.TestWriteToClosedPeerReportsError;
var
  LClient, LPeer: IAsyncSocket;
  LData: array[0..65535] of Byte;
  LStatus, LRounds: Integer;
  LDone: Boolean;
begin
  ConnectPair(LClient, LPeer);
  LPeer.Close;
  FLoop.RunOnce(20);
  FillChar(LData, SizeOf(LData), 7);
  LStatus := 0;
  LRounds := 0;
  { The first writes may still succeed; then the kernel reports EPIPE or
    ECONNRESET. Without MSG_NOSIGNAL the process would die of SIGPIPE. }
  while (LStatus = 0) and (LRounds < 50) do
  begin
    Inc(LRounds);
    LDone := False;
    LClient.AsyncWrite(@LData[0], SizeOf(LData),
      procedure(ABytes: NativeInt; AStatus: Integer)
      begin
        LStatus := AStatus;
        LDone := True;
      end);
    AssertTrue('Write completes', PumpUntil(function: Boolean begin Result := LDone; end));
  end;
  AssertTrue('Writing to a closed peer reports an error (status ' + IntToStr(LStatus) + ')', LStatus <> 0);
end;

procedure TBackendTestCase.TestCloseCompletesPendingRead;
var
  LClient, LPeer: IAsyncSocket;
  LBuf: array[0..15] of Byte;
  LStatus: Integer;
  LDone: Boolean;
begin
  ConnectPair(LClient, LPeer);
  LDone := False;
  LStatus := 0;
  LClient.AsyncRead(@LBuf[0], SizeOf(LBuf),
    procedure(ABytes: NativeInt; AStatus: Integer)
    begin
      LStatus := AStatus;
      LDone := True;
    end);
  LClient.Close;
  AssertTrue('Close completes the pending read', LDone);
  {$ifdef UNIX}
  AssertEquals('Status is ECANCELED', ESysECANCELED, LStatus);
  {$endif}
end;

procedure TBackendTestCase.TestLargeTransfer;
const
  Size = 4 * 1024 * 1024;
var
  LClient, LPeer: IAsyncSocket;
  LOut, LIn: array of Byte;
  LChunk: array[0..4095] of Byte;
  LReceived: Integer;
  LWriteDone: Boolean;
  LWriteStatus: Integer;
  I: Integer;
  ReadNext: reference to procedure;
begin
  ConnectPair(LClient, LPeer);
  SetLength(LOut, Size);
  SetLength(LIn, Size);
  for I := 0 to Size - 1 do
    LOut[I] := Byte(I * 7 + I shr 11);
  LReceived := 0;
  LWriteDone := False;
  LWriteStatus := -1;
  { The reader takes 4 KB at a time, so most of the data is still queued
    after each read: a level-triggered backend must report it again. }
  ReadNext := procedure
    begin
      LPeer.AsyncRead(@LChunk[0], SizeOf(LChunk),
        procedure(ABytes: NativeInt; AStatus: Integer)
        begin
          if ABytes > 0 then
          begin
            Move(LChunk[0], LIn[LReceived], ABytes);
            Inc(LReceived, ABytes);
            if LReceived < Size then
              ReadNext();
          end;
        end);
    end;
  ReadNext();
  LClient.AsyncWrite(@LOut[0], Size,
    procedure(ABytes: NativeInt; AStatus: Integer)
    begin
      LWriteStatus := AStatus;
      LWriteDone := True;
    end);
  AssertTrue('Transfer finished (' + IntToStr(LReceived) + ' bytes)',
    PumpUntil(function: Boolean begin Result := LWriteDone and (LReceived >= Size); end, 20000));
  AssertEquals('Write status', 0, LWriteStatus);
  AssertTrue('Data arrived intact', CompareByte(LOut[0], LIn[0], Size) = 0);
  ReadNext := nil;
end;

procedure TBackendTestCase.TestConnectRefusedCallsBack;
var
  LProbe: IAsyncServerSocket;
  LPort: Word;
  LClient: TAsyncSocket;
  LRef: IAsyncSocket;
  LCalled: Boolean;
  LConnected: Boolean;
begin
  { Find a free port, then close it again so nobody listens there. }
  LProbe := TEventLoop.CreateTcpServer(FLoop);
  LProbe.Listen('127.0.0.1', 0, 16, False);
  LPort := LProbe.Port;
  LProbe.Close;
  LProbe := nil;

  LCalled := False;
  LConnected := True;
  LClient := TAsyncSocket.Create(FLoop);
  LRef := LClient;
  try
    LClient.AsyncConnect('127.0.0.1', LPort, nil);
  except
    on E: ESocketException do
    begin
      { Some systems refuse at once; that is reported synchronously. }
      LCalled := True;
      LConnected := False;
    end;
  end;
  if not LCalled then
  begin
    AssertTrue('Loop keeps running after a refused connect',
      PumpUntil(function: Boolean begin Result := not LClient.IsConnected and (LClient.LastError <> 0); end));
    LConnected := LClient.IsConnected;
  end;
  AssertFalse('Not connected', LConnected);
  {$ifdef UNIX}
  if LClient.LastError <> 0 then
    AssertEquals('ECONNREFUSED', ESysECONNREFUSED, LClient.LastError);
  {$endif}
end;

procedure TBackendTestCase.TestHostNameIsRejected;
var
  LClient: IAsyncSocket;
  LRaised: Boolean;
begin
  LClient := TEventLoop.CreateTcpClient(FLoop);
  LRaised := False;
  try
    LClient.AsyncConnect('no-such-host.invalid', 80, nil);
  except
    on E: ESocketException do
      LRaised := True;
  end;
  AssertTrue('A host name is rejected instead of connecting to 0.0.0.0', LRaised);
end;

procedure TBackendTestCase.TestReadAsyncCancellation;
var
  LClient, LPeer: IAsyncSocket;
  LBuf: array[0..15] of Byte;
  LCTS: TCancellationTokenSource;
  LFut: specialize IFuture<NativeInt>;
  LCanceled: Boolean;
begin
  ConnectPair(LClient, LPeer);
  LCTS := TCancellationTokenSource.Create;
  try
    LFut := LClient.ReadAsync(@LBuf[0], SizeOf(LBuf), LCTS.Token);
    FLoop.RunOnce(10);
    AssertFalse('Read is pending', LFut.Wait(0));
    LCTS.Cancel;
    AssertTrue('Cancellation completes the future',
      PumpUntil(function: Boolean begin Result := LFut.Status = TTaskStatus.Canceled; end));
    LCanceled := False;
    try
      LFut.Value;
    except
      on E: EOperationCancelled do
        LCanceled := True;
    end;
    AssertTrue('Value raises EOperationCancelled', LCanceled);
    { The socket is usable again: a later read gets the data. }
    LBuf[0] := 0;
    LFut := LClient.ReadAsync(@LBuf[0], 1);
    LPeer.AsyncWrite(PAnsiChar('Z'), 1, TAsyncWriteCallback(nil));
    AssertTrue('Next read completes',
      PumpUntil(function: Boolean begin Result := LFut.Status = TTaskStatus.Completed; end));
    AssertEquals('Next read got the byte', Ord('Z'), LBuf[0]);
  finally
    LCTS.Free;
  end;
end;

procedure TBackendTestCase.TestAcceptAsyncIsOneShot;
var
  LFut1, LFut2: specialize IFuture<IAsyncSocket>;
  LC1, LC2: IAsyncSocket;
begin
  FServer := TEventLoop.CreateTcpServer(FLoop);
  FServer.Listen('127.0.0.1', 0);
  LFut1 := FServer.AcceptAsync;
  LC1 := TEventLoop.CreateTcpClient(FLoop);
  LC1.AsyncConnect('127.0.0.1', FServer.Port, nil);
  LC2 := TEventLoop.CreateTcpClient(FLoop);
  LC2.AsyncConnect('127.0.0.1', FServer.Port, nil);
  AssertTrue('First accept completes',
    PumpUntil(function: Boolean begin Result := LFut1.Status = TTaskStatus.Completed; end));
  AssertNotNull('First connection', LFut1.Value);
  { The handler of the first AcceptAsync is gone: running the loop with a
    second connection queued must neither crash nor accept it. }
  FLoop.RunOnce(50);
  LFut2 := FServer.AcceptAsync;
  AssertTrue('Second accept gets the queued connection',
    PumpUntil(function: Boolean begin Result := LFut2.Status = TTaskStatus.Completed; end));
  AssertNotNull('Second connection', LFut2.Value);
  AssertTrue('Two different connections', LFut1.Value.Handle <> LFut2.Value.Handle);
end;

procedure TBackendTestCase.TestAcceptAsyncCanceledByServerClose;
var
  LFut: specialize IFuture<IAsyncSocket>;
begin
  FServer := TEventLoop.CreateTcpServer(FLoop);
  FServer.Listen('127.0.0.1', 0);
  LFut := FServer.AcceptAsync;
  FLoop.RunOnce(10);
  FServer.Close;
  AssertTrue('Closing the server cancels the pending accept',
    PumpUntil(function: Boolean begin Result := LFut.Status = TTaskStatus.Canceled; end));
end;

procedure TBackendTestCase.TestReadAsyncCompletedByClose;
var
  LClient, LPeer: IAsyncSocket;
  LBuf: array[0..15] of Byte;
  LFut: specialize IFuture<NativeInt>;
begin
  ConnectPair(LClient, LPeer);
  LFut := LClient.ReadAsync(@LBuf[0], SizeOf(LBuf));
  FLoop.RunOnce(10);
  LClient.Close;
  AssertTrue('Closing the socket ends a pending ReadAsync',
    PumpUntil(function: Boolean begin Result := LFut.Status = TTaskStatus.Canceled; end));
end;

procedure TBackendTestCase.TestPipeEndOfFileAfterWriterClose;
var
  LPipe: IAsyncPipe;
  LBuf: array[0..15] of Byte;
  LReader: TPipeReader;
begin
  LPipe := TEventLoop.CreatePipe(FLoop);
  LReader := TPipeReader.Create;
  try
    LPipe.AsyncRead(@LBuf[0], SizeOf(LBuf), @LReader.OnRead);
    LPipe.CloseWriter;
    AssertTrue('Read completes after the writer closed',
      PumpUntil(function: Boolean begin Result := LReader.Done; end));
    AssertEquals('End of file', 0, LReader.Bytes);
  finally
    LReader.Free;
  end;
end;

procedure TBackendTestCase.TestPipeIdleAfterWriterCloseDoesNotSpin;
var
  LPipe: IAsyncPipe;
  LStart: QWord;
  LCalls: Integer;
begin
  LPipe := TEventLoop.CreatePipe(FLoop);
  LPipe.CloseWriter;
  LStart := GetTickCount64;
  LCalls := 0;
  while GetTickCount64 - LStart < 300 do
  begin
    FLoop.RunOnce(100);
    Inc(LCalls);
  end;
  AssertTrue('Idle read end without writer woke the loop ' + IntToStr(LCalls) + ' times', LCalls <= 6);
end;

procedure TBackendTestCase.TestPipeWriteWithoutReaderReportsEPipe;
var
  LPipe: IAsyncPipe;
  LByte: Byte;
  LWriter: TPipeWriter;
begin
  LPipe := TEventLoop.CreatePipe(FLoop);
  LPipe.CloseReader;
  LWriter := TPipeWriter.Create;
  try
    LByte := 1;
    LPipe.AsyncWrite(@LByte, 1, @LWriter.OnWrite);
    AssertTrue('Write completes', PumpUntil(function: Boolean begin Result := LWriter.Done; end));
    {$ifdef UNIX}
    AssertEquals('EPIPE instead of SIGPIPE', ESysEPIPE, LWriter.Status);
    {$endif}
  finally
    LWriter.Free;
  end;
end;

procedure TBackendTestCase.TestFileCreateIsWritable;
var
  LPath: string;
  LFile: IAsyncFile;
  LData: AnsiString;
  LBuf: array[0..31] of AnsiChar;
begin
  LPath := GetTempFileName('', 'elbt');
  try
    LFile := TEventLoop.OpenFile(LPath, fmCreate, FLoop);
    LData := 'written through fmCreate';
    AssertEquals('WriteAsync on a file opened with fmCreate',
      Length(LData), LFile.WriteAsync(PAnsiChar(LData), Length(LData), 0).Value);
    FillChar(LBuf, SizeOf(LBuf), 0);
    AssertEquals('Read it back at offset 0 (pread)', Length(LData),
      LFile.ReadAsync(@LBuf[0], Length(LData), 0).Value);
    AssertEquals('Content', LData, Copy(LBuf, 1, Length(LData)));
    AssertEquals('Read at an offset', 'through',
      Copy(LBuf, 1, LFile.ReadAsync(@LBuf[0], 7, 8).Value));
    LFile.Close;
  finally
    DeleteFile(LPath);
  end;
end;

procedure TBackendTestCase.TestFileReleasedWhileOperationPending;
var
  LPath: string;
  LFile: IAsyncFile;
  LData: AnsiString;
  LWriter: TPipeWriter;
begin
  LPath := GetTempFileName('', 'elbt');
  LWriter := TPipeWriter.Create;
  try
    LFile := TEventLoop.OpenFile(LPath, fmCreate, FLoop);
    LData := 'pending';
    LFile.AsyncWrite(PAnsiChar(LData), Length(LData), 0, @LWriter.OnWrite);
    { Drop the only reference while the write runs in the pool. }
    LFile := nil;
    AssertTrue('Callback arrives after the last reference was dropped',
      PumpUntil(function: Boolean begin Result := LWriter.Done; end));
    AssertEquals('Write succeeded', 0, LWriter.Status);
  finally
    LWriter.Free;
    DeleteFile(LPath);
  end;
end;

{ TTestEpollBackend }

function TTestEpollBackend.Backend: TEventLoopBackendKind;
begin
  Result := bkEpoll;
end;

{ TTestIOUringBackend }

function TTestIOUringBackend.Backend: TEventLoopBackendKind;
begin
  Result := bkIOUring;
end;

{ TTestEventLoopGroupLifetime }

procedure TTestEventLoopGroupLifetime.TestDestroyWithoutStart;
begin
  AssertTrue('Releasing a group that was never started does not hang',
    RunsWithin(
      procedure
      var
        LGroup: IEventLoopGroup;
      begin
        LGroup := TEventLoop.CreateGroup(2, bkEpoll);
        LGroup := nil;
      end, 5000));
end;

procedure TTestEventLoopGroupLifetime.TestStartStopWait;
begin
  AssertTrue('Start, then an immediate Stop and Wait, returns',
    RunsWithin(
      procedure
      var
        LGroup: IEventLoopGroup;
      begin
        LGroup := TEventLoop.CreateGroup(4, bkEpoll);
        LGroup.Start;
        LGroup.Stop; { may come before the threads have entered Run }
        LGroup.Wait;
        LGroup := nil;
      end, 5000));
end;

initialization
  RegisterTest(TTestEpollBackend);
  {$if defined(LINUX) or defined(ANDROID)}
  RegisterTest(TTestIOUringBackend);
  {$endif}
  RegisterTest(TTestEventLoopGroupLifetime);
end.
