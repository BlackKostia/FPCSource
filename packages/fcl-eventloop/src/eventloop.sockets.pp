{
    This file is part of the Free Component Library (FCL)
    Copyright (c) 2026 by the Free Pascal development team

    Scalable Asynchronous I/O Event Loop - Non-blocking TCP/UDP Sockets

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.
}
{$mode objfpc}{$H+}
{$modeswitch nestedprocvars}
{$modeswitch functionreferences}
{$modeswitch anonymousfunctions}
{$modeswitch advancedrecords}

unit eventloop.sockets;

interface

uses
  SysUtils, Classes, SyncObjs, System.Threading,
  eventloop.types, eventloop.core
  {$ifdef UNIX}, baseunix, sockets{$endif}
  {$ifdef MSWINDOWS}, Windows, WinSock2{$endif};

type
  IAsyncSocket = interface;

  { Non-blocking client / peer connection socket }
  IAsyncSocket = interface
    ['{84B2FE68-B234-4C23-8B37-646A94E27B10}']
    function GetHandle: TLoopHandle;
    function IsConnected: Boolean;
    procedure SetNoDelay(AValue: Boolean);
    procedure SetKeepAlive(AValue: Boolean);
    procedure AsyncConnect(const AHost: string; APort: Word; const ACallback: TAsyncCallback);
    procedure AsyncRead(ABuffer: Pointer; ACount: NativeInt; const ACallback: TAsyncReadCallback); overload;
    procedure AsyncRead(ABuffer: Pointer; ACount: NativeInt; const AProc: TAsyncReadProc); overload;
    procedure AsyncWrite(ABuffer: Pointer; ACount: NativeInt; const ACallback: TAsyncWriteCallback); overload;
    procedure AsyncWrite(ABuffer: Pointer; ACount: NativeInt; const AProc: TAsyncWriteProc); overload;
    function ReadAsync(ABuffer: Pointer; ACount: NativeInt; constref ACancellationToken: TCancellationToken): specialize IFuture<NativeInt>; overload;
    function ReadAsync(ABuffer: Pointer; ACount: NativeInt): specialize IFuture<NativeInt>; overload;
    function WriteAsync(ABuffer: Pointer; ACount: NativeInt; constref ACancellationToken: TCancellationToken): specialize IFuture<NativeInt>; overload;
    function WriteAsync(ABuffer: Pointer; ACount: NativeInt): specialize IFuture<NativeInt>; overload;
    procedure Close;
    property Handle: TLoopHandle read GetHandle;
    property Connected: Boolean read IsConnected;
  end;

  { Non-blocking server listening socket }
  IAsyncServerSocket = interface
    ['{91A7CB3F-7A9B-4D88-BBE8-4D2A572F8B70}']
    function GetHandle: TLoopHandle;
    function GetPort: Word;
    procedure Listen(const AHost: string; APort: Word = 0; ABacklog: Integer = 1024; AReusePort: Boolean = True);
    procedure AsyncAccept(const ACallback: TAsyncAcceptCallback); overload;
    procedure AsyncAccept(const AProc: TAsyncAcceptProc); overload;
    function AcceptAsync(constref ACancellationToken: TCancellationToken): specialize IFuture<IAsyncSocket>; overload;
    function AcceptAsync: specialize IFuture<IAsyncSocket>; overload;
    procedure Close;
    property Handle: TLoopHandle read GetHandle;
    property Port: Word read GetPort;
  end;

  { Non-blocking UDP datagram socket }
  IAsyncDatagramSocket = interface
    ['{3A94D290-E577-448F-A392-D08C19485C66}']
    function GetHandle: TLoopHandle;
    procedure Bind(const AHost: string; APort: Word);
    function SendTo(const AHost: string; APort: Word; ABuffer: Pointer; ACount: Integer): Integer;
    procedure Close;
    property Handle: TLoopHandle read GetHandle;
  end;

  { Implementation classes.

    All Async* methods and Close must be called in the loop thread (or before
    the loop runs). The *Async methods that return futures can be called from
    any thread: they hand the operation over to the loop thread. }
  TAsyncSocket = class(TInterfacedObject, IAsyncSocket)
  private
    FHandle: TLoopHandle;
    FLoop: IEventLoop;
    FOwnsHandle: Boolean;
    FConnected: Boolean;
    FConnecting: Boolean;
    FConnectCallback: TAsyncCallback;
    FLastError: Integer;
    FDestroying: Boolean;

    { Registration with the loop: a socket is registered only while an
      operation is pending, so an idle socket whose peer has gone away does
      not make a level-triggered poller report hang-up over and over. }
    FRegistered: Boolean;
    FInterest: TEventLoopEvents;

    { Pending read }
    FReadBuffer: Pointer;
    FReadCount: NativeInt;
    FReadCallback: TAsyncReadCallback;
    FReadProc: TAsyncReadProc;
    FReadGen: Cardinal;

    { Pending write }
    FWriteBuffer: Pointer;
    FWriteCount: NativeInt;
    FWriteOffset: NativeInt;
    FWriteCallback: TAsyncWriteCallback;
    FWriteProc: TAsyncWriteProc;
    FWriteGen: Cardinal;

    procedure HandleIO(AHandle: TLoopHandle; AEvents: TEventLoopEvents; AUserData: Pointer);
    procedure SetNonBlocking(AHandle: TLoopHandle);
    procedure SetInterest(AEvents: TEventLoopEvents);
    procedure UpdateLoopEvents;
    function HasPendingRead: Boolean; inline;
    function HasPendingWrite: Boolean; inline;
    procedure CompleteRead(ABytes: NativeInt; AStatus: Integer);
    procedure CompleteWrite(ABytes: NativeInt; AStatus: Integer);
    procedure DoRecv;
    procedure DoSend;
    procedure CancelRead(AGen: Cardinal);
    procedure CancelWrite(AGen: Cardinal);
  public
    constructor Create(ALoop: IEventLoop; AHandle: TLoopHandle = -1; AConnected: Boolean = False);
    destructor Destroy; override;

    function GetHandle: TLoopHandle;
    function IsConnected: Boolean;
    procedure SetNoDelay(AValue: Boolean);
    procedure SetKeepAlive(AValue: Boolean);
    procedure AsyncConnect(const AHost: string; APort: Word; const ACallback: TAsyncCallback);
    procedure AsyncRead(ABuffer: Pointer; ACount: NativeInt; const ACallback: TAsyncReadCallback); overload;
    procedure AsyncRead(ABuffer: Pointer; ACount: NativeInt; const AProc: TAsyncReadProc); overload;
    procedure AsyncWrite(ABuffer: Pointer; ACount: NativeInt; const ACallback: TAsyncWriteCallback); overload;
    procedure AsyncWrite(ABuffer: Pointer; ACount: NativeInt; const AProc: TAsyncWriteProc); overload;
    function ReadAsync(ABuffer: Pointer; ACount: NativeInt; constref ACancellationToken: TCancellationToken): specialize IFuture<NativeInt>; overload;
    function ReadAsync(ABuffer: Pointer; ACount: NativeInt): specialize IFuture<NativeInt>; overload;
    function WriteAsync(ABuffer: Pointer; ACount: NativeInt; constref ACancellationToken: TCancellationToken): specialize IFuture<NativeInt>; overload;
    function WriteAsync(ABuffer: Pointer; ACount: NativeInt): specialize IFuture<NativeInt>; overload;
    procedure Close;
    { errno of the last failed asynchronous connect, 0 otherwise }
    property LastError: Integer read FLastError;
  end;

  TAsyncServerSocket = class(TInterfacedObject, IAsyncServerSocket)
  private
    FHandle: TLoopHandle;
    FLoop: IEventLoop;
    FAcceptCallback: TAsyncAcceptCallback;
    FAcceptProc: TAsyncAcceptProc;
    FAcceptGen: Cardinal;
    FRegistered: Boolean;
    FDestroying: Boolean;

    procedure HandleIO(AHandle: TLoopHandle; AEvents: TEventLoopEvents; AUserData: Pointer);
    procedure SetNonBlocking(AHandle: TLoopHandle);
    procedure UpdateLoopEvents;
    procedure CancelAccept(AGen: Cardinal);
  public
    constructor Create(ALoop: IEventLoop);
    destructor Destroy; override;

    function GetHandle: TLoopHandle;
    function GetPort: Word;
    procedure Listen(const AHost: string; APort: Word = 0; ABacklog: Integer = 1024; AReusePort: Boolean = True);
    procedure AsyncAccept(const ACallback: TAsyncAcceptCallback); overload;
    procedure AsyncAccept(const AProc: TAsyncAcceptProc); overload;
    function AcceptAsync(constref ACancellationToken: TCancellationToken): specialize IFuture<IAsyncSocket>; overload;
    function AcceptAsync: specialize IFuture<IAsyncSocket>; overload;
    procedure Close;
    property Port: Word read GetPort;
  end;

implementation

uses
  eventloop.promise;

const
  {$if defined(LINUX) or defined(ANDROID)}
  SO_REUSEPORT_CONST = 15;
  { Report EPIPE instead of raising SIGPIPE, which would end the process }
  SEND_FLAGS = $4000; { MSG_NOSIGNAL }
  {$elseif defined(FREEBSD) or defined(DRAGONFLY)}
  SO_REUSEPORT_CONST = $200;
  SEND_FLAGS = $20000; { MSG_NOSIGNAL }
  {$elseif defined(OPENBSD) or defined(NETBSD)}
  SO_REUSEPORT_CONST = $200;
  SEND_FLAGS = $400; { MSG_NOSIGNAL }
  {$elseif defined(DARWIN)}
  SO_REUSEPORT_CONST = $200;
  SEND_FLAGS = 0; { SO_NOSIGPIPE is set on the socket instead }
  SO_NOSIGPIPE_CONST = $1022;
  {$else}
  SO_REUSEPORT_CONST = 0;
  SEND_FLAGS = 0;
  {$endif}
  TCP_NODELAY_CONST = 1;
  {$ifdef UNIX}
  ERR_CANCELED = ESysECANCELED;
  {$else}
  ERR_CANCELED = 995; { ERROR_OPERATION_ABORTED }
  {$endif}

type
  TSizePromise = specialize TLoopPromise<NativeInt>;
  TSocketPromise = specialize TLoopPromise<IAsyncSocket>;

{ Helper procedures }

procedure SetSocketNonBlocking(AHandle: TLoopHandle);
{$ifdef UNIX}
var
  LFlags: cint;
begin
  LFlags := fpfcntl(AHandle, F_GETFL, 0);
  if LFlags >= 0 then
    fpfcntl(AHandle, F_SETFL, LFlags or O_NONBLOCK);
  {$ifdef DARWIN}
  LFlags := 1;
  fpsetsockopt(AHandle, SOL_SOCKET, SO_NOSIGPIPE_CONST, @LFlags, SizeOf(LFlags));
  {$endif}
end;
{$endif}
{$ifdef MSWINDOWS}
var
  LMode: u_long;
begin
  LMode := 1;
  ioctlsocket(AHandle, FIONBIO, @LMode);
end;
{$endif}

function ParseIPv4(const AHost: string; ADefaultLoopback: Boolean): in_addr;
begin
  if (AHost = '') or (AHost = 'localhost') then
  begin
    if ADefaultLoopback then
      Result := StrToNetAddr('127.0.0.1')
    else
      Result.s_addr := 0;
    Exit;
  end;
  if AHost = '0.0.0.0' then
  begin
    Result.s_addr := 0;
    Exit;
  end;
  Result := StrToNetAddr(AHost);
  { StrToNetAddr returns 0.0.0.0 for anything it cannot parse; connecting
    there would silently reach the local host. }
  if Result.s_addr = 0 then
    raise ESocketException.CreateFmt('"%s" is not an IPv4 address (host names are not resolved)', [AHost]);
end;

{ Runs AProc in the loop thread: directly when already there, otherwise
  through Post. }
procedure RunInLoop(const ALoop: IEventLoop; const AProc: TAsyncProc);
begin
  if ALoop.InLoopThread then
    AProc()
  else
    ALoop.Post(AProc);
end;

{ TAsyncSocket }

constructor TAsyncSocket.Create(ALoop: IEventLoop; AHandle: TLoopHandle; AConnected: Boolean);
begin
  inherited Create;
  FLoop := ALoop;
  FHandle := AHandle;
  FConnected := AConnected;
  FOwnsHandle := True;
  if FHandle <> InvalidLoopHandle then
    SetNonBlocking(FHandle);
end;

destructor TAsyncSocket.Destroy;
begin
  { Pending callbacks are dropped, not called, when the socket goes away. }
  FDestroying := True;
  Close;
  inherited Destroy;
end;

function TAsyncSocket.GetHandle: TLoopHandle;
begin
  Result := FHandle;
end;

function TAsyncSocket.IsConnected: Boolean;
begin
  Result := FConnected;
end;

procedure TAsyncSocket.SetNonBlocking(AHandle: TLoopHandle);
begin
  SetSocketNonBlocking(AHandle);
end;

procedure TAsyncSocket.SetNoDelay(AValue: Boolean);
var
  LOpt: cint;
begin
  if FHandle = InvalidLoopHandle then
    Exit;
  LOpt := Ord(AValue);
  {$ifdef UNIX}
  fpsetsockopt(FHandle, 6 {IPPROTO_TCP}, TCP_NODELAY_CONST, @LOpt, SizeOf(LOpt));
  {$endif}
  {$ifdef MSWINDOWS}
  setsockopt(FHandle, IPPROTO_TCP, TCP_NODELAY, PAnsiChar(@LOpt), SizeOf(LOpt));
  {$endif}
end;

procedure TAsyncSocket.SetKeepAlive(AValue: Boolean);
var
  LOpt: cint;
begin
  if FHandle = InvalidLoopHandle then
    Exit;
  LOpt := Ord(AValue);
  {$ifdef UNIX}
  fpsetsockopt(FHandle, SOL_SOCKET, SO_KEEPALIVE, @LOpt, SizeOf(LOpt));
  {$endif}
  {$ifdef MSWINDOWS}
  setsockopt(FHandle, SOL_SOCKET, SO_KEEPALIVE, PAnsiChar(@LOpt), SizeOf(LOpt));
  {$endif}
end;

function TAsyncSocket.HasPendingRead: Boolean;
begin
  Result := Assigned(FReadCallback) or Assigned(FReadProc);
end;

function TAsyncSocket.HasPendingWrite: Boolean;
begin
  Result := Assigned(FWriteCallback) or Assigned(FWriteProc);
end;

procedure TAsyncSocket.SetInterest(AEvents: TEventLoopEvents);
begin
  if (FHandle = InvalidLoopHandle) or (FLoop = nil) then
    Exit;
  if (AEvents = FInterest) and (FRegistered = (AEvents <> [])) then
    Exit;
  if AEvents = [] then
  begin
    if FRegistered then
      FLoop.UnregisterHandle(FHandle);
    FRegistered := False;
  end
  else if FRegistered then
    FLoop.ModifyHandle(FHandle, AEvents)
  else
  begin
    FLoop.RegisterHandle(FHandle, AEvents, @HandleIO, Self);
    FRegistered := True;
  end;
  FInterest := AEvents;
end;

procedure TAsyncSocket.UpdateLoopEvents;
var
  LEvents: TEventLoopEvents;
begin
  LEvents := [];
  if FConnecting then
    LEvents := [eleWrite]
  else
  begin
    if HasPendingRead then
      Include(LEvents, eleRead);
    if HasPendingWrite then
      Include(LEvents, eleWrite);
  end;
  SetInterest(LEvents);
end;

procedure TAsyncSocket.CompleteRead(ABytes: NativeInt; AStatus: Integer);
var
  LCb: TAsyncReadCallback;
  LProc: TAsyncReadProc;
begin
  { Take the callback first: it may start the next read right away. }
  LCb := FReadCallback;
  LProc := FReadProc;
  FReadCallback := nil;
  FReadProc := nil;
  if Assigned(LCb) then
    LCb(ABytes, AStatus)
  else if Assigned(LProc) then
    LProc(ABytes, AStatus);
end;

procedure TAsyncSocket.CompleteWrite(ABytes: NativeInt; AStatus: Integer);
var
  LCb: TAsyncWriteCallback;
  LProc: TAsyncWriteProc;
begin
  LCb := FWriteCallback;
  LProc := FWriteProc;
  FWriteCallback := nil;
  FWriteProc := nil;
  if Assigned(LCb) then
    LCb(ABytes, AStatus)
  else if Assigned(LProc) then
    LProc(ABytes, AStatus);
end;

procedure TAsyncSocket.DoRecv;
{$ifdef UNIX}
var
  LBytes: NativeInt;
  LErr: cint;
begin
  LBytes := fprecv(FHandle, FReadBuffer, FReadCount, 0);
  if LBytes >= 0 then
    CompleteRead(LBytes, 0) { 0 bytes: the peer closed the connection }
  else
  begin
    LErr := fpgeterrno;
    if (LErr <> ESysEAGAIN) and (LErr <> ESysEWOULDBLOCK) and (LErr <> ESysEINTR) then
      CompleteRead(-1, LErr);
  end;
end;
{$else}
begin
end;
{$endif}

procedure TAsyncSocket.DoSend;
{$ifdef UNIX}
var
  LBytes: NativeInt;
  LErr: cint;
begin
  LBytes := fpsend(FHandle, PByte(FWriteBuffer) + FWriteOffset, FWriteCount - FWriteOffset, SEND_FLAGS);
  if LBytes >= 0 then
  begin
    Inc(FWriteOffset, LBytes);
    if FWriteOffset >= FWriteCount then
      CompleteWrite(FWriteOffset, 0);
  end
  else
  begin
    LErr := fpgeterrno;
    if (LErr <> ESysEAGAIN) and (LErr <> ESysEWOULDBLOCK) and (LErr <> ESysEINTR) then
      CompleteWrite(-1, LErr);
  end;
end;
{$else}
begin
end;
{$endif}

procedure TAsyncSocket.AsyncConnect(const AHost: string; APort: Word; const ACallback: TAsyncCallback);
var
  LAddr: TInetSockAddr;
  LRes: cint;
  LErr: cint;
begin
  FillChar(LAddr, SizeOf(LAddr), 0);
  LAddr.sin_family := AF_INET;
  LAddr.sin_port := htons(APort);
  LAddr.sin_addr := ParseIPv4(AHost, True);

  if FHandle = InvalidLoopHandle then
  begin
    {$ifdef UNIX}
    FHandle := fpsocket(AF_INET, SOCK_STREAM, 0);
    {$endif}
    {$ifdef MSWINDOWS}
    FHandle := socket(AF_INET, SOCK_STREAM, 0);
    {$endif}
    if FHandle = InvalidLoopHandle then
      raise ESocketException.Create('Failed to create socket');
    SetNonBlocking(FHandle);
  end;

  FConnectCallback := ACallback;
  FConnecting := True;
  FLastError := 0;

  {$ifdef UNIX}
  LRes := fpconnect(FHandle, @LAddr, SizeOf(LAddr));
  if LRes = 0 then
  begin
    { Connected synchronously }
    FConnecting := False;
    FConnected := True;
    FConnectCallback := nil;
    UpdateLoopEvents;
    if Assigned(ACallback) then
      ACallback();
  end
  else
  begin
    LErr := fpgeterrno;
    if (LErr = ESysEINPROGRESS) or (LErr = ESysEWOULDBLOCK) then
      UpdateLoopEvents
    else
    begin
      FConnecting := False;
      FConnectCallback := nil;
      FLastError := LErr;
      raise ESocketException.CreateFmt('Connect failed: %s (errno=%d)', [SysErrorMessage(LErr), LErr]);
    end;
  end;
  {$endif}
end;

procedure TAsyncSocket.AsyncRead(ABuffer: Pointer; ACount: NativeInt; const ACallback: TAsyncReadCallback);
begin
  FReadBuffer := ABuffer;
  FReadCount := ACount;
  FReadCallback := ACallback;
  FReadProc := nil;
  Inc(FReadGen);
  UpdateLoopEvents;
end;

procedure TAsyncSocket.AsyncRead(ABuffer: Pointer; ACount: NativeInt; const AProc: TAsyncReadProc);
begin
  FReadBuffer := ABuffer;
  FReadCount := ACount;
  FReadCallback := nil;
  FReadProc := AProc;
  Inc(FReadGen);
  UpdateLoopEvents;
end;

procedure TAsyncSocket.AsyncWrite(ABuffer: Pointer; ACount: NativeInt; const ACallback: TAsyncWriteCallback);
begin
  FWriteBuffer := ABuffer;
  FWriteCount := ACount;
  FWriteOffset := 0;
  FWriteCallback := ACallback;
  FWriteProc := nil;
  Inc(FWriteGen);
  { Eager write: most writes fit into the socket buffer and complete here
    without a round trip through the poller. }
  if (FHandle <> InvalidLoopHandle) and FConnected and (not FConnecting) then
    DoSend;
  UpdateLoopEvents;
end;

procedure TAsyncSocket.AsyncWrite(ABuffer: Pointer; ACount: NativeInt; const AProc: TAsyncWriteProc);
begin
  FWriteBuffer := ABuffer;
  FWriteCount := ACount;
  FWriteOffset := 0;
  FWriteCallback := nil;
  FWriteProc := AProc;
  Inc(FWriteGen);
  if (FHandle <> InvalidLoopHandle) and FConnected and (not FConnecting) then
    DoSend;
  UpdateLoopEvents;
end;

procedure TAsyncSocket.HandleIO(AHandle: TLoopHandle; AEvents: TEventLoopEvents; AUserData: Pointer);
var
  LKeep: IAsyncSocket;
  LConnCb: TAsyncCallback;
  {$ifdef UNIX}
  LOptLen: TSockLen;
  LVal: cint;
  {$endif}
begin
  { A callback may drop the last reference to this socket. }
  LKeep := Self;
  if FConnecting then
  begin
    FConnecting := False;
    {$ifdef UNIX}
    LOptLen := SizeOf(LVal);
    LVal := 0;
    if fpgetsockopt(FHandle, SOL_SOCKET, SO_ERROR, @LVal, @LOptLen) < 0 then
      LVal := fpgeterrno;
    FLastError := LVal;
    FConnected := LVal = 0;
    {$endif}
    LConnCb := FConnectCallback;
    FConnectCallback := nil;
    UpdateLoopEvents;
    { The callback is called on failure too: Connected is False then and
      LastError holds the error. Raising here would end the loop's Run. }
    if Assigned(LConnCb) then
      LConnCb();
    Exit;
  end;

  { Hang-up and error are delivered to pending operations: recv/send then
    return end-of-file or the error, so they complete instead of waiting
    for an event that never comes. }
  if HasPendingRead and (AEvents * [eleRead, eleHangup, eleError] <> []) and (FHandle <> InvalidLoopHandle) then
    DoRecv;
  if HasPendingWrite and (AEvents * [eleWrite, eleHangup, eleError] <> []) and (FHandle <> InvalidLoopHandle) then
    DoSend;
  UpdateLoopEvents;
end;

procedure TAsyncSocket.CancelRead(AGen: Cardinal);
begin
  if (FReadGen = AGen) and HasPendingRead then
  begin
    FReadCallback := nil;
    FReadProc := nil;
    UpdateLoopEvents;
  end;
end;

procedure TAsyncSocket.CancelWrite(AGen: Cardinal);
begin
  if (FWriteGen = AGen) and HasPendingWrite then
  begin
    FWriteCallback := nil;
    FWriteProc := nil;
    UpdateLoopEvents;
  end;
end;

type
  { State shared by a future-based operation, its completion callback and
    its cancellation callback. }
  TSocketOp = class(TInterfacedObject)
  public
    Promise: TSizePromise;
    PromiseRef: IInterface;
    Socket: TAsyncSocket;
    SocketRef: IAsyncSocket; { keeps Socket alive }
    Loop: IEventLoop;
    Gen: Cardinal;
    Registration: TCancellationTokenRegistration;
    procedure Complete(ABytes: NativeInt; AStatus: Integer);
  end;

procedure TSocketOp.Complete(ABytes: NativeInt; AStatus: Integer);
begin
  Registration.Unregister;
  if AStatus = ERR_CANCELED then
    Promise.TrySetCanceled
  else if AStatus <> 0 then
    Promise.TrySetException(ESocketException.CreateFmt('Async socket error %d: %s', [AStatus, SysErrorMessage(AStatus)]))
  else
    Promise.TrySetResult(ABytes);
end;

function StartSocketOp(ASocket: TAsyncSocket; ABuffer: Pointer; ACount: NativeInt;
  constref AToken: TCancellationToken; AWrite: Boolean): specialize IFuture<NativeInt>;
var
  LOp: TSocketOp;
  LOpRef: IInterface;
begin
  LOp := TSocketOp.Create;
  LOpRef := LOp;
  LOp.Promise := TSizePromise.Create;
  LOp.PromiseRef := LOp.Promise;
  LOp.Socket := ASocket;
  LOp.SocketRef := ASocket;
  LOp.Loop := ASocket.FLoop;
  Result := LOp.Promise.Future;
  if AToken.IsCancellationRequested then
  begin
    LOp.Promise.TrySetCanceled;
    Exit;
  end;
  if LOp.Loop = nil then
  begin
    LOp.Promise.TrySetException(ESocketException.Create('Socket has no event loop'));
    Exit;
  end;

  RunInLoop(LOp.Loop,
    procedure
    var
      LSock: TAsyncSocket;
    begin
      if LOpRef = nil then;
      if not LOp.Promise.IsPending then
        Exit; { canceled before it could start }
      LSock := LOp.Socket;
      { The completion closure holds the operation until it has run. }
      if AWrite then
      begin
        LSock.AsyncWrite(ABuffer, ACount,
          procedure(ABytes: NativeInt; AStatus: Integer)
          begin
            if LOpRef = nil then;
            LOp.Complete(ABytes, AStatus);
          end);
        LOp.Gen := LSock.FWriteGen;
      end
      else
      begin
        LSock.AsyncRead(ABuffer, ACount,
          procedure(ABytes: NativeInt; AStatus: Integer)
          begin
            if LOpRef = nil then;
            LOp.Complete(ABytes, AStatus);
          end);
        LOp.Gen := LSock.FReadGen;
      end;
    end);

  if AToken.CanBeCanceled then
    LOp.Registration := AToken.Register(
      procedure
      begin
        { Cancellation can come from any thread; the socket is only
          touched in the loop thread. }
        LOp.Loop.Post(
          procedure
          begin
            if LOpRef = nil then;
            if not LOp.Promise.IsPending then
              Exit;
            if AWrite then
              LOp.Socket.CancelWrite(LOp.Gen)
            else
              LOp.Socket.CancelRead(LOp.Gen);
            LOp.Promise.TrySetCanceled;
          end);
      end);
end;

function TAsyncSocket.ReadAsync(ABuffer: Pointer; ACount: NativeInt; constref ACancellationToken: TCancellationToken): specialize IFuture<NativeInt>;
begin
  Result := StartSocketOp(Self, ABuffer, ACount, ACancellationToken, False);
end;

function TAsyncSocket.ReadAsync(ABuffer: Pointer; ACount: NativeInt): specialize IFuture<NativeInt>;
begin
  Result := ReadAsync(ABuffer, ACount, TCancellationToken.None);
end;

function TAsyncSocket.WriteAsync(ABuffer: Pointer; ACount: NativeInt; constref ACancellationToken: TCancellationToken): specialize IFuture<NativeInt>;
begin
  Result := StartSocketOp(Self, ABuffer, ACount, ACancellationToken, True);
end;

function TAsyncSocket.WriteAsync(ABuffer: Pointer; ACount: NativeInt): specialize IFuture<NativeInt>;
begin
  Result := WriteAsync(ABuffer, ACount, TCancellationToken.None);
end;

procedure TAsyncSocket.Close;
var
  LKeep: IAsyncSocket;
  LHadRead, LHadWrite: Boolean;
  LReadCb: TAsyncReadCallback;
  LReadProc: TAsyncReadProc;
  LWriteCb: TAsyncWriteCallback;
  LWriteProc: TAsyncWriteProc;
  LConnCb: TAsyncCallback;
begin
  if not FDestroying then
    LKeep := Self;
  LReadCb := FReadCallback;
  LReadProc := FReadProc;
  LWriteCb := FWriteCallback;
  LWriteProc := FWriteProc;
  LConnCb := FConnectCallback;
  LHadRead := HasPendingRead;
  LHadWrite := HasPendingWrite;
  FReadCallback := nil;
  FReadProc := nil;
  FWriteCallback := nil;
  FWriteProc := nil;
  FConnectCallback := nil;

  if FHandle <> InvalidLoopHandle then
  begin
    if FRegistered and (FLoop <> nil) then
      FLoop.UnregisterHandle(FHandle);
    FRegistered := False;
    FInterest := [];
    if FOwnsHandle then
    begin
      {$ifdef UNIX}
      fpclose(FHandle);
      {$endif}
      {$ifdef MSWINDOWS}
      closesocket(FHandle);
      {$endif}
    end;
    FHandle := InvalidLoopHandle;
  end;
  FConnected := False;
  FConnecting := False;

  if FDestroying then
    Exit;
  { Operations still pending complete with ECANCELED, so that futures and
    fibers waiting for them do not hang. }
  if LHadRead then
    if Assigned(LReadCb) then
      LReadCb(-1, ERR_CANCELED)
    else
      LReadProc(-1, ERR_CANCELED);
  if LHadWrite then
    if Assigned(LWriteCb) then
      LWriteCb(-1, ERR_CANCELED)
    else
      LWriteProc(-1, ERR_CANCELED);
  if Assigned(LConnCb) then
  begin
    FLastError := ERR_CANCELED;
    LConnCb();
  end;
end;

{ TAsyncServerSocket }

constructor TAsyncServerSocket.Create(ALoop: IEventLoop);
begin
  inherited Create;
  FLoop := ALoop;
  FHandle := InvalidLoopHandle;
end;

destructor TAsyncServerSocket.Destroy;
begin
  FDestroying := True;
  FAcceptCallback := nil;
  FAcceptProc := nil;
  Close;
  inherited Destroy;
end;

function TAsyncServerSocket.GetHandle: TLoopHandle;
begin
  Result := FHandle;
end;

function TAsyncServerSocket.GetPort: Word;
var
  LAddr: TInetSockAddr;
  LLen: TSockLen;
begin
  Result := 0;
  if FHandle = InvalidLoopHandle then
    Exit;
  LLen := SizeOf(LAddr);
  FillChar(LAddr, SizeOf(LAddr), 0);
  {$ifdef UNIX}
  if fpgetsockname(FHandle, @LAddr, @LLen) = 0 then
    Result := ntohs(LAddr.sin_port);
  {$endif}
  {$ifdef MSWINDOWS}
  if getsockname(FHandle, TSockAddr(LAddr), LLen) = 0 then
    Result := ntohs(LAddr.sin_port);
  {$endif}
end;

procedure TAsyncServerSocket.SetNonBlocking(AHandle: TLoopHandle);
begin
  SetSocketNonBlocking(AHandle);
end;

procedure TAsyncServerSocket.UpdateLoopEvents;
var
  LWant: Boolean;
begin
  if (FHandle = InvalidLoopHandle) or (FLoop = nil) then
    Exit;
  { Listen only while somebody accepts; otherwise a pending connection
    would make a level-triggered poller report the socket again and again. }
  LWant := Assigned(FAcceptCallback) or Assigned(FAcceptProc);
  if LWant = FRegistered then
    Exit;
  if LWant then
    FLoop.RegisterHandle(FHandle, [eleRead], @HandleIO, Self)
  else
    FLoop.UnregisterHandle(FHandle);
  FRegistered := LWant;
end;

procedure TAsyncServerSocket.Listen(const AHost: string; APort: Word; ABacklog: Integer; AReusePort: Boolean);
var
  LAddr: TInetSockAddr;
  LOpt: cint;
begin
  Close;

  FillChar(LAddr, SizeOf(LAddr), 0);
  LAddr.sin_family := AF_INET;
  LAddr.sin_port := htons(APort);
  LAddr.sin_addr := ParseIPv4(AHost, False);

  {$ifdef UNIX}
  FHandle := fpsocket(AF_INET, SOCK_STREAM, 0);
  if FHandle < 0 then
  begin
    FHandle := InvalidLoopHandle;
    raise ESocketException.CreateFmt('Socket creation failed: %s (errno=%d)', [SysErrorMessage(fpgeterrno), fpgeterrno]);
  end;

  LOpt := 1;
  fpsetsockopt(FHandle, SOL_SOCKET, SO_REUSEADDR, @LOpt, SizeOf(LOpt));
  if AReusePort and (SO_REUSEPORT_CONST <> 0) then
    fpsetsockopt(FHandle, SOL_SOCKET, SO_REUSEPORT_CONST, @LOpt, SizeOf(LOpt));

  SetNonBlocking(FHandle);

  if fpbind(FHandle, @LAddr, SizeOf(LAddr)) < 0 then
  begin
    LOpt := fpgeterrno;
    Close;
    raise ESocketException.CreateFmt('Bind to %s:%d failed: %s (errno=%d)', [AHost, APort, SysErrorMessage(LOpt), LOpt]);
  end;

  if fplisten(FHandle, ABacklog) < 0 then
  begin
    LOpt := fpgeterrno;
    Close;
    raise ESocketException.CreateFmt('Listen failed: %s (errno=%d)', [SysErrorMessage(LOpt), LOpt]);
  end;

  UpdateLoopEvents;
  {$endif}
end;

procedure TAsyncServerSocket.AsyncAccept(const ACallback: TAsyncAcceptCallback);
begin
  FAcceptCallback := ACallback;
  FAcceptProc := nil;
  Inc(FAcceptGen);
  UpdateLoopEvents;
end;

procedure TAsyncServerSocket.AsyncAccept(const AProc: TAsyncAcceptProc);
begin
  FAcceptCallback := nil;
  FAcceptProc := AProc;
  Inc(FAcceptGen);
  UpdateLoopEvents;
end;

procedure TAsyncServerSocket.HandleIO(AHandle: TLoopHandle; AEvents: TEventLoopEvents; AUserData: Pointer);
var
  LKeep: IAsyncServerSocket;
  LCb: TAsyncAcceptCallback;
  LProc: TAsyncAcceptProc;
  {$ifdef UNIX}
  LClient: cint;
  LAddr: TInetSockAddr;
  LAddrLen: TSockLen;
  LErr: cint;
  {$endif}
begin
  LKeep := Self;
  if not (eleRead in AEvents) then
    Exit;
  {$ifdef UNIX}
  while FHandle <> InvalidLoopHandle do
  begin
    { Copy the handler before calling it: it may replace or clear itself,
      as AcceptAsync's one-shot handler does. }
    LCb := FAcceptCallback;
    LProc := FAcceptProc;
    if not (Assigned(LCb) or Assigned(LProc)) then
      Break;
    LAddrLen := SizeOf(LAddr);
    LClient := fpaccept(FHandle, @LAddr, @LAddrLen);
    if LClient >= 0 then
    begin
      SetNonBlocking(LClient);
      if Assigned(LCb) then
        LCb(LClient, NetAddrToStr(LAddr.sin_addr), ntohs(LAddr.sin_port), 0)
      else
        LProc(LClient, NetAddrToStr(LAddr.sin_addr), ntohs(LAddr.sin_port), 0);
    end
    else
    begin
      LErr := fpgeterrno;
      if (LErr <> ESysEAGAIN) and (LErr <> ESysEWOULDBLOCK) and (LErr <> ESysEINTR) then
      begin
        if Assigned(LCb) then
          LCb(InvalidLoopHandle, '', 0, LErr)
        else
          LProc(InvalidLoopHandle, '', 0, LErr);
      end;
      Break;
    end;
  end;
  {$endif}
  UpdateLoopEvents;
end;

procedure TAsyncServerSocket.CancelAccept(AGen: Cardinal);
begin
  if FAcceptGen = AGen then
  begin
    FAcceptCallback := nil;
    FAcceptProc := nil;
    UpdateLoopEvents;
  end;
end;

type
  TAcceptOp = class(TInterfacedObject)
  public
    Promise: TSocketPromise;
    PromiseRef: IInterface;
    Server: TAsyncServerSocket;
    ServerRef: IAsyncServerSocket; { keeps Server alive }
    Loop: IEventLoop;
    Gen: Cardinal;
    Registration: TCancellationTokenRegistration;
  end;

function TAsyncServerSocket.AcceptAsync(constref ACancellationToken: TCancellationToken): specialize IFuture<IAsyncSocket>;
var
  LOp: TAcceptOp;
  LOpRef: IInterface;
begin
  LOp := TAcceptOp.Create;
  LOpRef := LOp;
  LOp.Promise := TSocketPromise.Create;
  LOp.PromiseRef := LOp.Promise;
  LOp.Server := Self;
  LOp.ServerRef := Self;
  LOp.Loop := FLoop;
  Result := LOp.Promise.Future;
  if ACancellationToken.IsCancellationRequested then
  begin
    LOp.Promise.TrySetCanceled;
    Exit;
  end;
  if FLoop = nil then
  begin
    LOp.Promise.TrySetException(ESocketException.Create('Server socket has no event loop'));
    Exit;
  end;

  RunInLoop(FLoop,
    procedure
    var
      LServer: TAsyncServerSocket;
    begin
      if LOpRef = nil then;
      if not LOp.Promise.IsPending then
        Exit;
      LServer := LOp.Server;
      { One-shot handler: it removes itself after the first connection. }
      LServer.AsyncAccept(
        procedure(AClientHandle: TLoopHandle; const AClientAddr: string; AClientPort: Word; AStatus: Integer)
        begin
          if LOpRef = nil then;
          LServer.CancelAccept(LOp.Gen);
          LOp.Registration.Unregister;
          if AStatus = ERR_CANCELED then
            LOp.Promise.TrySetCanceled
          else if AStatus <> 0 then
            LOp.Promise.TrySetException(ESocketException.CreateFmt('Accept failed: %s (errno=%d)', [SysErrorMessage(AStatus), AStatus]))
          else if not LOp.Promise.TrySetResult(TAsyncSocket.Create(LOp.Loop, AClientHandle, True)) then
            ; { canceled meanwhile: the new socket is released and closed }
        end);
      LOp.Gen := LServer.FAcceptGen;
    end);

  if ACancellationToken.CanBeCanceled then
    LOp.Registration := ACancellationToken.Register(
      procedure
      begin
        LOp.Loop.Post(
          procedure
          begin
            if LOpRef = nil then;
            if not LOp.Promise.IsPending then
              Exit;
            LOp.Server.CancelAccept(LOp.Gen);
            LOp.Promise.TrySetCanceled;
          end);
      end);
end;

function TAsyncServerSocket.AcceptAsync: specialize IFuture<IAsyncSocket>;
begin
  Result := AcceptAsync(TCancellationToken.None);
end;

procedure TAsyncServerSocket.Close;
var
  LKeep: IAsyncServerSocket;
  LCb: TAsyncAcceptCallback;
  LProc: TAsyncAcceptProc;
begin
  LCb := nil;
  LProc := nil;
  if not FDestroying then
  begin
    LKeep := Self;
    LCb := FAcceptCallback;
    LProc := FAcceptProc;
  end;
  FAcceptCallback := nil;
  FAcceptProc := nil;
  if FHandle <> InvalidLoopHandle then
  begin
    if FRegistered and (FLoop <> nil) then
      FLoop.UnregisterHandle(FHandle);
    FRegistered := False;
    {$ifdef UNIX}
    fpclose(FHandle);
    {$endif}
    {$ifdef MSWINDOWS}
    closesocket(FHandle);
    {$endif}
    FHandle := InvalidLoopHandle;
  end;
  { A pending accept learns that it will not get a connection. }
  if Assigned(LCb) then
    LCb(InvalidLoopHandle, '', 0, ERR_CANCELED)
  else if Assigned(LProc) then
    LProc(InvalidLoopHandle, '', 0, ERR_CANCELED);
end;

end.
