{
    This file is part of the Free Component Library (FCL)
    Copyright (c) 2026 by the Free Pascal development team

    Scalable Asynchronous I/O Event Loop - Asynchronous File Operations

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.
}
{$mode objfpc}{$H+}
{$modeswitch nestedprocvars}
{$modeswitch functionreferences}
{$modeswitch anonymousfunctions}

unit eventloop.files;

interface

uses
  SysUtils, Classes, SyncObjs, System.Threading,
  eventloop.types, eventloop.core
  {$ifdef UNIX}, baseunix{$endif}
  {$ifdef MSWINDOWS}, Windows{$endif};

type
  IAsyncFile = interface
    ['{69A27F11-3E2A-4B6E-85F0-18DCEE348601}']
    function GetHandle: TLoopHandle;
    function GetSize: Int64;
    procedure AsyncRead(ABuffer: Pointer; ACount: NativeInt; AOffset: Int64; const ACallback: TAsyncReadCallback);
    procedure AsyncWrite(ABuffer: Pointer; ACount: NativeInt; AOffset: Int64; const ACallback: TAsyncWriteCallback);
    function ReadAsync(ABuffer: Pointer; ACount: NativeInt; AOffset: Int64; constref ACancellationToken: TCancellationToken): specialize IFuture<NativeInt>; overload;
    function ReadAsync(ABuffer: Pointer; ACount: NativeInt; AOffset: Int64 = -1): specialize IFuture<NativeInt>; overload;
    function WriteAsync(ABuffer: Pointer; ACount: NativeInt; AOffset: Int64; constref ACancellationToken: TCancellationToken): specialize IFuture<NativeInt>; overload;
    function WriteAsync(ABuffer: Pointer; ACount: NativeInt; AOffset: Int64 = -1): specialize IFuture<NativeInt>; overload;
    procedure Close;
    property Handle: TLoopHandle read GetHandle;
    property Size: Int64 read GetSize;
  end;

  TAsyncFile = class(TInterfacedObject, IAsyncFile)
  private
    FLoop: IEventLoop;
    FHandle: TLoopHandle;
    FFileName: string;
    FFileMode: Integer;
    FOwnsHandle: Boolean;
    FLock: TCriticalSection;
  public
    constructor Open(const AFileName: string; AMode: Integer; ALoop: IEventLoop = nil);
    destructor Destroy; override;

    function GetHandle: TLoopHandle;
    function GetSize: Int64;
    procedure AsyncRead(ABuffer: Pointer; ACount: NativeInt; AOffset: Int64; const ACallback: TAsyncReadCallback);
    procedure AsyncWrite(ABuffer: Pointer; ACount: NativeInt; AOffset: Int64; const ACallback: TAsyncWriteCallback);
    function ReadAsync(ABuffer: Pointer; ACount: NativeInt; AOffset: Int64; constref ACancellationToken: TCancellationToken): specialize IFuture<NativeInt>; overload;
    function ReadAsync(ABuffer: Pointer; ACount: NativeInt; AOffset: Int64 = -1): specialize IFuture<NativeInt>; overload;
    function WriteAsync(ABuffer: Pointer; ACount: NativeInt; AOffset: Int64; constref ACancellationToken: TCancellationToken): specialize IFuture<NativeInt>; overload;
    function WriteAsync(ABuffer: Pointer; ACount: NativeInt; AOffset: Int64 = -1): specialize IFuture<NativeInt>; overload;
    procedure Close;
  end;

implementation

{ Reads or writes at AOffset, or at the current position when AOffset < 0.
  Called with the file lock held. }
function FileIO(AHandle: TLoopHandle; ABuffer: Pointer; ACount: NativeInt; AOffset: Int64;
  AWrite: Boolean; out AErr: Integer): NativeInt;
begin
  AErr := 0;
  {$ifdef UNIX}
  if AOffset >= 0 then
  begin
    if AWrite then
      Result := FpPWrite(AHandle, ABuffer, ACount, AOffset)
    else
      Result := FpPRead(AHandle, ABuffer, ACount, AOffset);
  end
  else if AWrite then
    Result := fpwrite(AHandle, ABuffer^, ACount)
  else
    Result := fpread(AHandle, ABuffer^, ACount);
  if Result < 0 then
    AErr := fpgeterrno;
  {$else}
  Result := -1;
  AErr := 0;
  {$endif}
end;

constructor TAsyncFile.Open(const AFileName: string; AMode: Integer; ALoop: IEventLoop);
{$ifdef UNIX}
var
  LFlags: cint;
begin
  inherited Create;
  FLoop := ALoop;
  FFileName := AFileName;
  FFileMode := AMode;
  FOwnsHandle := True;
  FLock := TCriticalSection.Create;

  case AMode and 3 of
    fmOpenWrite: LFlags := O_WRONLY;
    fmOpenReadWrite: LFlags := O_RDWR;
  else
    LFlags := O_RDONLY;
  end;
  { fmCreate ($FF00) has no access bits of its own; like TFileStream, a
    created file is opened for reading and writing. }
  if (AMode and fmCreate) = fmCreate then
  begin
    if (AMode and 3) = fmOpenRead then
      LFlags := O_RDWR;
    LFlags := LFlags or O_CREAT or O_TRUNC;
  end;

  FHandle := fpopen(PAnsiChar(AFileName), LFlags, &664);
  if FHandle < 0 then
    raise EEventLoopException.CreateFmt('Failed to open file "%s": %s (errno=%d)', [AFileName, SysErrorMessage(fpgeterrno), fpgeterrno]);
end;
{$else}
begin
  inherited Create;
  FLoop := ALoop;
  FFileName := AFileName;
  FFileMode := AMode;
  FOwnsHandle := True;
  FLock := TCriticalSection.Create;
  raise EEventLoopException.Create('AsyncFile not implemented on this platform');
end;
{$endif}

destructor TAsyncFile.Destroy;
begin
  Close;
  FreeAndNil(FLock);
  inherited Destroy;
end;

function TAsyncFile.GetHandle: TLoopHandle;
begin
  Result := FHandle;
end;

function TAsyncFile.GetSize: Int64;
{$ifdef UNIX}
var
  LStat: Stat;
begin
  if (FHandle = InvalidLoopHandle) or (fpfstat(FHandle, LStat) < 0) then
    Result := 0
  else
    Result := LStat.st_size;
end;
{$else}
begin
  Result := 0;
end;
{$endif}

procedure TAsyncFile.AsyncRead(ABuffer: Pointer; ACount: NativeInt; AOffset: Int64; const ACallback: TAsyncReadCallback);
var
  LKeep: IAsyncFile;
  LLoop: IEventLoop;
begin
  { The task holds the file until it has run. }
  LKeep := Self;
  LLoop := FLoop;
  TTask.Run(
    procedure
    var
      LRes: NativeInt;
      LErr: Integer;
    begin
      FLock.Acquire;
      try
        LRes := FileIO(FHandle, ABuffer, ACount, AOffset, False, LErr);
      finally
        FLock.Release;
      end;
      if not Assigned(ACallback) then
        Exit;
      if LLoop <> nil then
        LLoop.Post(
          procedure
          begin
            if LKeep = nil then;
            ACallback(LRes, LErr);
          end)
      else
        ACallback(LRes, LErr);
    end);
end;

procedure TAsyncFile.AsyncWrite(ABuffer: Pointer; ACount: NativeInt; AOffset: Int64; const ACallback: TAsyncWriteCallback);
var
  LKeep: IAsyncFile;
  LLoop: IEventLoop;
begin
  LKeep := Self;
  LLoop := FLoop;
  TTask.Run(
    procedure
    var
      LRes: NativeInt;
      LErr: Integer;
    begin
      FLock.Acquire;
      try
        LRes := FileIO(FHandle, ABuffer, ACount, AOffset, True, LErr);
      finally
        FLock.Release;
      end;
      if not Assigned(ACallback) then
        Exit;
      if LLoop <> nil then
        LLoop.Post(
          procedure
          begin
            if LKeep = nil then;
            ACallback(LRes, LErr);
          end)
      else
        ACallback(LRes, LErr);
    end);
end;

function TAsyncFile.ReadAsync(ABuffer: Pointer; ACount: NativeInt; AOffset: Int64; constref ACancellationToken: TCancellationToken): specialize IFuture<NativeInt>;
var
  LKeep: IAsyncFile;
begin
  LKeep := Self;
  Result := TTask.specialize Future<NativeInt>(
    function: NativeInt
    var
      LErr: Integer;
    begin
      if LKeep = nil then;
      ACancellationToken.ThrowIfCancellationRequested;
      FLock.Acquire;
      try
        Result := FileIO(FHandle, ABuffer, ACount, AOffset, False, LErr);
      finally
        FLock.Release;
      end;
      if Result < 0 then
        raise EEventLoopException.CreateFmt('File read failed: %s (errno=%d)', [SysErrorMessage(LErr), LErr]);
    end,
    ACancellationToken,
    nil
  );
end;

function TAsyncFile.ReadAsync(ABuffer: Pointer; ACount: NativeInt; AOffset: Int64): specialize IFuture<NativeInt>;
begin
  Result := ReadAsync(ABuffer, ACount, AOffset, TCancellationToken.None);
end;

function TAsyncFile.WriteAsync(ABuffer: Pointer; ACount: NativeInt; AOffset: Int64; constref ACancellationToken: TCancellationToken): specialize IFuture<NativeInt>;
var
  LKeep: IAsyncFile;
begin
  LKeep := Self;
  Result := TTask.specialize Future<NativeInt>(
    function: NativeInt
    var
      LErr: Integer;
    begin
      if LKeep = nil then;
      ACancellationToken.ThrowIfCancellationRequested;
      FLock.Acquire;
      try
        Result := FileIO(FHandle, ABuffer, ACount, AOffset, True, LErr);
      finally
        FLock.Release;
      end;
      if Result < 0 then
        raise EEventLoopException.CreateFmt('File write failed: %s (errno=%d)', [SysErrorMessage(LErr), LErr]);
    end,
    ACancellationToken,
    nil
  );
end;

function TAsyncFile.WriteAsync(ABuffer: Pointer; ACount: NativeInt; AOffset: Int64): specialize IFuture<NativeInt>;
begin
  Result := WriteAsync(ABuffer, ACount, AOffset, TCancellationToken.None);
end;

procedure TAsyncFile.Close;
begin
  FLock.Acquire;
  try
    if (FHandle <> InvalidLoopHandle) and FOwnsHandle then
    begin
      {$ifdef UNIX}
      fpclose(FHandle);
      {$endif}
      FHandle := InvalidLoopHandle;
    end;
  finally
    FLock.Release;
  end;
end;

end.
