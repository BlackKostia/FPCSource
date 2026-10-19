{
    This file is part of the Free Component Library (FCL)
    Copyright (c) 2026 by the Free Pascal development team

    Scalable Asynchronous I/O Event Loop - Non-blocking Pipes

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.
}
{$mode objfpc}{$H+}
{$modeswitch nestedprocvars}

unit eventloop.pipes;

interface

uses
  SysUtils, Classes, eventloop.types, eventloop.core
  {$ifdef UNIX}, baseunix{$endif}
  {$if defined(LINUX) or defined(ANDROID)}, syscall{$endif}
  {$ifdef MSWINDOWS}, Windows{$endif};

type
  IAsyncPipe = interface
    ['{DCB9B08F-DF31-4F2A-A801-D36C5BE55490}']
    function GetReaderHandle: TLoopHandle;
    function GetWriterHandle: TLoopHandle;
    procedure AsyncRead(ABuffer: Pointer; ACount: NativeInt; const ACallback: TAsyncReadCallback);
    procedure AsyncWrite(ABuffer: Pointer; ACount: NativeInt; const ACallback: TAsyncWriteCallback);
    procedure CloseReader;
    procedure CloseWriter;
    procedure Close;
    property ReaderHandle: TLoopHandle read GetReaderHandle;
    property WriterHandle: TLoopHandle read GetWriterHandle;
  end;

  { Both ends are registered with the loop only while an operation on them
    is pending: a read end whose writer has been closed is reported as hung
    up over and over by a level-triggered poller otherwise. }
  TAsyncPipe = class(TInterfacedObject, IAsyncPipe)
  private
    FLoop: IEventLoop;
    FReadHandle: TLoopHandle;
    FWriteHandle: TLoopHandle;
    FReadRegistered: Boolean;
    FWriteRegistered: Boolean;
    FDestroying: Boolean;

    FReadBuffer: Pointer;
    FReadCount: NativeInt;
    FReadCallback: TAsyncReadCallback;

    FWriteBuffer: Pointer;
    FWriteCount: NativeInt;
    FWriteOffset: NativeInt;
    FWriteCallback: TAsyncWriteCallback;

    procedure HandleReadIO(AHandle: TLoopHandle; AEvents: TEventLoopEvents; AUserData: Pointer);
    procedure HandleWriteIO(AHandle: TLoopHandle; AEvents: TEventLoopEvents; AUserData: Pointer);
    procedure SetReadInterest(AWant: Boolean);
    procedure SetWriteInterest(AWant: Boolean);
    procedure DoRead;
    procedure DoWrite;
  public
    constructor Create(ALoop: IEventLoop);
    destructor Destroy; override;

    function GetReaderHandle: TLoopHandle;
    function GetWriterHandle: TLoopHandle;
    procedure AsyncRead(ABuffer: Pointer; ACount: NativeInt; const ACallback: TAsyncReadCallback);
    procedure AsyncWrite(ABuffer: Pointer; ACount: NativeInt; const ACallback: TAsyncWriteCallback);
    { Closing an end with a pending operation completes it with ECANCELED. }
    procedure CloseReader;
    procedure CloseWriter;
    procedure Close;
  end;

implementation

const
  {$ifdef UNIX}
  ERR_CANCELED = ESysECANCELED;
  {$else}
  ERR_CANCELED = 995;
  {$endif}

{$ifdef UNIX}
var
  SigPipeChecked: Boolean = False;

{ Writing to a pipe whose read end is closed raises SIGPIPE, which ends the
  process by default. Unless the program installed its own handler, ignore
  the signal so that the write fails with EPIPE instead. }
procedure IgnoreSigPipe;
var
  LOld, LNew: SigActionRec;
begin
  if SigPipeChecked then
    Exit;
  SigPipeChecked := True;
  FillChar(LOld, SizeOf(LOld), 0);
  if FpSigAction(SIGPIPE, nil, @LOld) <> 0 then
    Exit;
  if LOld.sa_handler <> SigActionHandler(SIG_DFL) then
    Exit;
  FillChar(LNew, SizeOf(LNew), 0);
  LNew.sa_handler := SigActionHandler(SIG_IGN);
  FpSigAction(SIGPIPE, @LNew, nil);
end;
{$endif}

constructor TAsyncPipe.Create(ALoop: IEventLoop);
{$ifdef UNIX}
var
  LPipes: array[0..1] of cint;
  LRes: cint;
begin
  inherited Create;
  FLoop := ALoop;
  FReadHandle := InvalidLoopHandle;
  FWriteHandle := InvalidLoopHandle;
  IgnoreSigPipe;

  {$if defined(LINUX) or defined(ANDROID)}
  LRes := cint(Do_SysCall(syscall_nr_pipe2, TSysParam(@LPipes[0]), O_NONBLOCK or $80000 {O_CLOEXEC}));
  {$else}
  LRes := -1;
  {$endif}
  if LRes < 0 then
  begin
    if fppipe(LPipes) < 0 then
      raise EEventLoopException.CreateFmt('fppipe failed: %s (errno=%d)', [SysErrorMessage(fpgeterrno), fpgeterrno]);
    fpfcntl(LPipes[0], F_SETFL, O_NONBLOCK);
    fpfcntl(LPipes[1], F_SETFL, O_NONBLOCK);
  end;

  FReadHandle := LPipes[0];
  FWriteHandle := LPipes[1];
end;
{$else}
begin
  inherited Create;
  FLoop := ALoop;
  FReadHandle := InvalidLoopHandle;
  FWriteHandle := InvalidLoopHandle;
  raise EEventLoopException.Create('Pipes not implemented on this platform');
end;
{$endif}

destructor TAsyncPipe.Destroy;
begin
  FDestroying := True;
  Close;
  inherited Destroy;
end;

function TAsyncPipe.GetReaderHandle: TLoopHandle;
begin
  Result := FReadHandle;
end;

function TAsyncPipe.GetWriterHandle: TLoopHandle;
begin
  Result := FWriteHandle;
end;

procedure TAsyncPipe.SetReadInterest(AWant: Boolean);
begin
  if (FLoop = nil) or (FReadHandle = InvalidLoopHandle) or (AWant = FReadRegistered) then
    Exit;
  if AWant then
    FLoop.RegisterHandle(FReadHandle, [eleRead], @HandleReadIO, Self)
  else
    FLoop.UnregisterHandle(FReadHandle);
  FReadRegistered := AWant;
end;

procedure TAsyncPipe.SetWriteInterest(AWant: Boolean);
begin
  if (FLoop = nil) or (FWriteHandle = InvalidLoopHandle) or (AWant = FWriteRegistered) then
    Exit;
  if AWant then
    FLoop.RegisterHandle(FWriteHandle, [eleWrite], @HandleWriteIO, Self)
  else
    FLoop.UnregisterHandle(FWriteHandle);
  FWriteRegistered := AWant;
end;

procedure TAsyncPipe.AsyncRead(ABuffer: Pointer; ACount: NativeInt; const ACallback: TAsyncReadCallback);
begin
  FReadBuffer := ABuffer;
  FReadCount := ACount;
  FReadCallback := ACallback;
  SetReadInterest(Assigned(FReadCallback));
end;

procedure TAsyncPipe.AsyncWrite(ABuffer: Pointer; ACount: NativeInt; const ACallback: TAsyncWriteCallback);
begin
  FWriteBuffer := ABuffer;
  FWriteCount := ACount;
  FWriteOffset := 0;
  FWriteCallback := ACallback;
  { Eager write: usually the pipe has room and the write completes here. }
  if FWriteHandle <> InvalidLoopHandle then
    DoWrite;
  SetWriteInterest(Assigned(FWriteCallback) and (FWriteOffset < FWriteCount));
end;

procedure TAsyncPipe.DoRead;
{$ifdef UNIX}
var
  LBytes: NativeInt;
  LCb: TAsyncReadCallback;
  LErr: cint;
begin
  LBytes := fpread(FReadHandle, FReadBuffer^, FReadCount);
  if LBytes < 0 then
  begin
    LErr := fpgeterrno;
    if (LErr = ESysEAGAIN) or (LErr = ESysEWOULDBLOCK) or (LErr = ESysEINTR) then
      Exit;
  end
  else
    LErr := 0;
  { 0 bytes: all writers are closed (end of file) }
  LCb := FReadCallback;
  FReadCallback := nil;
  if LBytes < 0 then
    LCb(-1, LErr)
  else
    LCb(LBytes, 0);
end;
{$else}
begin
end;
{$endif}

procedure TAsyncPipe.DoWrite;
{$ifdef UNIX}
var
  LBytes: NativeInt;
  LCb: TAsyncWriteCallback;
  LErr: cint;
begin
  LBytes := fpwrite(FWriteHandle, (PByte(FWriteBuffer) + FWriteOffset)^, FWriteCount - FWriteOffset);
  if LBytes >= 0 then
  begin
    Inc(FWriteOffset, LBytes);
    if FWriteOffset < FWriteCount then
      Exit;
    LCb := FWriteCallback;
    FWriteCallback := nil;
    if Assigned(LCb) then
      LCb(FWriteOffset, 0);
  end
  else
  begin
    LErr := fpgeterrno;
    if (LErr = ESysEAGAIN) or (LErr = ESysEWOULDBLOCK) or (LErr = ESysEINTR) then
      Exit;
    { EPIPE when the read end has been closed }
    LCb := FWriteCallback;
    FWriteCallback := nil;
    FWriteOffset := FWriteCount;
    if Assigned(LCb) then
      LCb(-1, LErr);
  end;
end;
{$else}
begin
end;
{$endif}

procedure TAsyncPipe.HandleReadIO(AHandle: TLoopHandle; AEvents: TEventLoopEvents; AUserData: Pointer);
var
  LKeep: IAsyncPipe;
begin
  LKeep := Self;
  { Hang-up without data (writer closed) must also complete the read: the
    read then returns end of file. }
  if Assigned(FReadCallback) and (AEvents * [eleRead, eleHangup, eleError] <> []) then
    DoRead;
  SetReadInterest(Assigned(FReadCallback));
end;

procedure TAsyncPipe.HandleWriteIO(AHandle: TLoopHandle; AEvents: TEventLoopEvents; AUserData: Pointer);
var
  LKeep: IAsyncPipe;
begin
  LKeep := Self;
  if Assigned(FWriteCallback) and (AEvents * [eleWrite, eleHangup, eleError] <> []) then
    DoWrite;
  SetWriteInterest(Assigned(FWriteCallback) and (FWriteOffset < FWriteCount));
end;

procedure TAsyncPipe.CloseReader;
var
  LKeep: IAsyncPipe;
  LCb: TAsyncReadCallback;
begin
  if not FDestroying then
    LKeep := Self;
  LCb := FReadCallback;
  FReadCallback := nil;
  if FReadHandle <> InvalidLoopHandle then
  begin
    SetReadInterest(False);
    {$ifdef UNIX}
    fpclose(FReadHandle);
    {$endif}
    FReadHandle := InvalidLoopHandle;
  end;
  if Assigned(LCb) and not FDestroying then
    LCb(-1, ERR_CANCELED);
end;

procedure TAsyncPipe.CloseWriter;
var
  LKeep: IAsyncPipe;
  LCb: TAsyncWriteCallback;
begin
  if not FDestroying then
    LKeep := Self;
  LCb := FWriteCallback;
  FWriteCallback := nil;
  if FWriteHandle <> InvalidLoopHandle then
  begin
    SetWriteInterest(False);
    {$ifdef UNIX}
    fpclose(FWriteHandle);
    {$endif}
    FWriteHandle := InvalidLoopHandle;
  end;
  if Assigned(LCb) and not FDestroying then
    LCb(-1, ERR_CANCELED);
end;

procedure TAsyncPipe.Close;
begin
  CloseReader;
  CloseWriter;
end;

end.
