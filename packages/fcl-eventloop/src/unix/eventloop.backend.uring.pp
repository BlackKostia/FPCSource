{
    This file is part of the Free Component Library (FCL)
    Copyright (c) 2026 by the Free Pascal development team

    Scalable Asynchronous I/O Event Loop - Linux io_uring Backend

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.
}
{$mode objfpc}{$H+}
{$modeswitch nestedprocvars}

unit eventloop.backend.uring;

interface

{$if defined(LINUX) or defined(ANDROID)}

uses
  SysUtils, Classes, SyncObjs, BaseUnix, Unix, Linux, Syscall, eventloop.types, eventloop.core;

const
  { io_uring opcodes }
  IORING_OP_NOP         = 0;
  IORING_OP_READV       = 1;
  IORING_OP_WRITEV      = 2;
  IORING_OP_FSYNC       = 3;
  IORING_OP_POLL_ADD    = 6;
  IORING_OP_POLL_REMOVE = 7;
  IORING_OP_TIMEOUT     = 11;
  IORING_OP_ACCEPT      = 13;
  IORING_OP_CONNECT     = 16;
  IORING_OP_READ        = 22;
  IORING_OP_WRITE       = 23;

  { Magic offsets for mmap }
  IORING_OFF_SQ_RING    = 0;
  IORING_OFF_CQ_RING    = $8000000;
  IORING_OFF_SQES       = $10000000;

  { io_uring_enter flags }
  IORING_ENTER_GETEVENTS = 1;

type
  { io_uring Submission Queue Entry (64 bytes) }
  Pio_uring_sqe = ^Tio_uring_sqe;
  Tio_uring_sqe = record
    opcode: cuint8;
    flags: cuint8;
    ioprio: cuint16;
    fd: cint32;
    off: cuint64;
    addr: cuint64;
    len: cuint32;
    rw_flags: cuint32;
    user_data: cuint64;
    buf_index: cuint16;
    personality: cuint16;
    splice_fd_in: cint32;
    addr3: cuint64;
    pad2: cuint64;
  end;

  { io_uring Completion Queue Entry (16 bytes) }
  Pio_uring_cqe = ^Tio_uring_cqe;
  Tio_uring_cqe = record
    user_data: cuint64;
    res: cint32;
    flags: cuint32;
  end;

  { Layout offsets inside mmapped ring buffers }
  Tio_sqring_offsets = record
    head: cuint32;
    tail: cuint32;
    ring_mask: cuint32;
    ring_entries: cuint32;
    flags: cuint32;
    dropped: cuint32;
    array_offset: cuint32;
    resv1: cuint32;
    user_addr: cuint64;
  end;

  Tio_cqring_offsets = record
    head: cuint32;
    tail: cuint32;
    ring_mask: cuint32;
    ring_entries: cuint32;
    overflow: cuint32;
    cqes: cuint32;
    flags: cuint32;
    resv1: cuint32;
    user_addr: cuint64;
  end;

  { io_uring setup parameters }
  Pio_uring_params = ^Tio_uring_params;
  Tio_uring_params = record
    sq_entries: cuint32;
    cq_entries: cuint32;
    flags: cuint32;
    sq_thread_cpu: cuint32;
    sq_thread_idle: cuint32;
    features: cuint32;
    wq_fd: cuint32;
    resv: array[0..2] of cuint32;
    sq_off: Tio_sqring_offsets;
    cq_off: Tio_cqring_offsets;
  end;

  { struct __kernel_timespec, used by IORING_OP_TIMEOUT }
  Tio_kernel_timespec = record
    tv_sec: cint64;
    tv_nsec: cint64;
  end;

  { High-performance io_uring event loop engine.

    Readiness is reported with one-shot IORING_OP_POLL_ADD requests that are
    re-armed after each completion with the events currently registered for
    the handle. The user_data of a poll request holds the handle and a
    generation number, so completions of requests that were removed or
    replaced (POLL_REMOVE, ModifyHandle) are recognized and dropped. }
  TIOUringEventLoop = class(TEventLoopBase)
  private
    FRingFd: cint;
    FParams: Tio_uring_params;

    { Mmapped SQ ring pointers }
    FSQRingPtr: Pointer;
    FSQRingSize: size_t;
    FSQHead: PCuint32;
    FSQTail: PCuint32;
    FSQRingMask: cuint32;
    FSQEntries: cuint32;
    FSQArray: PCuint32;
    FSQEs: Pio_uring_sqe;
    FSQEsSize: size_t;

    { Mmapped CQ ring pointers }
    FCQRingPtr: Pointer;
    FCQRingSize: size_t;
    FCQHead: PCuint32;
    FCQTail: PCuint32;
    FCQRingMask: cuint32;
    FCQEs: Pio_uring_cqe;

    FWakeupFd: cint;
    FTimeout: Tio_kernel_timespec;

    { Serializes writes to the submission ring: handles may be registered or
      modified from other threads while the loop thread waits in DoPoll. }
    FSubmitLock: TCriticalSection;
    { Per-handle state, indexed by handle; guarded by FSubmitLock }
    FPollGen: array of cuint32;
    FPollMask: array of cuint16;
    FPollArmed: array of Boolean;

    function EventsToPollMask(AEvents: TEventLoopEvents): cuint16;
    function PollMaskToEvents(AMask: cint32): TEventLoopEvents;
    procedure EnsureHandleSlot(AHandle: TLoopHandle);
    function PollUserData(AHandle: TLoopHandle): cuint64; inline;
    procedure QueueSQE(constref ASQE: Tio_uring_sqe);
    procedure QueuePollAdd(AHandle: TLoopHandle);
    procedure QueuePollRemove(AHandle: TLoopHandle);
    procedure QueueWakeupPoll;
    procedure SubmitPending;
  protected
    procedure DoRegisterHandle(AHandle: TLoopHandle; AEvents: TEventLoopEvents; const ACallback: TAsyncIOCompletion; AUserData: Pointer); override;
    procedure DoModifyHandle(AHandle: TLoopHandle; AEvents: TEventLoopEvents); override;
    procedure DoUnregisterHandle(AHandle: TLoopHandle); override;
    procedure DoPoll(ATimeoutMs: Integer); override;
    procedure DoWakeup; override;
  public
    class function IsSupported: Boolean; static;
    constructor Create(AQueueDepth: Integer = 256);
    destructor Destroy; override;
    property RingFd: cint read FRingFd;
  end;

{$endif}

implementation

{$if defined(LINUX) or defined(ANDROID)}

const
  MAP_POPULATE_CONST = $8000;
  POLLIN_CONST  = $0001;
  POLLPRI_CONST = $0002;
  POLLOUT_CONST = $0004;
  POLLERR_CONST = $0008;
  POLLHUP_CONST = $0010;

  { user_data values that do not belong to a handle poll }
  UD_KIND_MASK   = QWord($FFFFFFFF00000000);
  UD_SPECIAL     = QWord($FFFFFFFF00000000);
  UD_WAKEUP      = UD_SPECIAL or 1;
  UD_TIMEOUT     = UD_SPECIAL or 2;
  UD_POLL_REMOVE = UD_SPECIAL or 3;

{ Reads a ring index written by the kernel; later reads of ring entries must
  not be moved before it. }
function LoadAcquire(P: PCuint32): cuint32; inline;
begin
  Result := P^;
  ReadBarrier;
end;

{ TIOUringEventLoop }

class function TIOUringEventLoop.IsSupported: Boolean;
var
  LParams: Tio_uring_params;
  LFd: cint;
begin
  FillChar(LParams, SizeOf(LParams), 0);
  LFd := cint(Do_SysCall(syscall_nr_io_uring_setup, 16, TSysParam(@LParams)));
  if LFd >= 0 then
  begin
    fpclose(LFd);
    Result := True;
  end
  else
    Result := False;
end;

constructor TIOUringEventLoop.Create(AQueueDepth: Integer);
begin
  inherited Create(bkIOUring);
  FRingFd := -1;
  FWakeupFd := -1;
  FSubmitLock := TCriticalSection.Create;
  FillChar(FParams, SizeOf(FParams), 0);
  if AQueueDepth < 16 then
    AQueueDepth := 16;

  FRingFd := cint(Do_SysCall(syscall_nr_io_uring_setup, AQueueDepth, TSysParam(@FParams)));
  if FRingFd < 0 then
    raise EEventLoopException.CreateFmt('io_uring_setup failed: %s (errno=%d)', [SysErrorMessage(fpgeterrno), fpgeterrno]);

  { 1. Map Submission Queue ring }
  FSQRingSize := FParams.sq_off.array_offset + FParams.sq_entries * SizeOf(cuint32);
  FSQRingPtr := fpmmap(nil, FSQRingSize, PROT_READ or PROT_WRITE, MAP_SHARED or MAP_POPULATE_CONST, FRingFd, IORING_OFF_SQ_RING);
  if FSQRingPtr = MAP_FAILED then
  begin
    FSQRingPtr := nil;
    raise EEventLoopException.Create('Failed to mmap io_uring SQ ring');
  end;

  FSQHead := PCuint32(PByte(FSQRingPtr) + FParams.sq_off.head);
  FSQTail := PCuint32(PByte(FSQRingPtr) + FParams.sq_off.tail);
  FSQRingMask := PCuint32(PByte(FSQRingPtr) + FParams.sq_off.ring_mask)^;
  FSQEntries := PCuint32(PByte(FSQRingPtr) + FParams.sq_off.ring_entries)^;
  FSQArray := PCuint32(PByte(FSQRingPtr) + FParams.sq_off.array_offset);

  { 2. Map Submission Queue Entries array }
  FSQEsSize := FParams.sq_entries * SizeOf(Tio_uring_sqe);
  FSQEs := Pio_uring_sqe(fpmmap(nil, FSQEsSize, PROT_READ or PROT_WRITE, MAP_SHARED or MAP_POPULATE_CONST, FRingFd, IORING_OFF_SQES));
  if Pointer(FSQEs) = MAP_FAILED then
  begin
    FSQEs := nil;
    raise EEventLoopException.Create('Failed to mmap io_uring SQEs');
  end;

  { 3. Map Completion Queue ring }
  FCQRingSize := FParams.cq_off.cqes + FParams.cq_entries * SizeOf(Tio_uring_cqe);
  FCQRingPtr := fpmmap(nil, FCQRingSize, PROT_READ or PROT_WRITE, MAP_SHARED or MAP_POPULATE_CONST, FRingFd, IORING_OFF_CQ_RING);
  if FCQRingPtr = MAP_FAILED then
  begin
    FCQRingPtr := nil;
    raise EEventLoopException.Create('Failed to mmap io_uring CQ ring');
  end;

  FCQHead := PCuint32(PByte(FCQRingPtr) + FParams.cq_off.head);
  FCQTail := PCuint32(PByte(FCQRingPtr) + FParams.cq_off.tail);
  FCQRingMask := PCuint32(PByte(FCQRingPtr) + FParams.cq_off.ring_mask)^;
  FCQEs := Pio_uring_cqe(PByte(FCQRingPtr) + FParams.cq_off.cqes);

  { Wakeup eventfd, polled like any other handle }
  FWakeupFd := cint(Do_SysCall(syscall_nr_eventfd2, 0, $80000 {EFD_CLOEXEC} or $800 {EFD_NONBLOCK}));
  if FWakeupFd < 0 then
    raise EEventLoopException.CreateFmt('eventfd2 failed: %s (errno=%d)', [SysErrorMessage(fpgeterrno), fpgeterrno]);
  FSubmitLock.Acquire;
  try
    QueueWakeupPoll;
    SubmitPending;
  finally
    FSubmitLock.Release;
  end;
end;

destructor TIOUringEventLoop.Destroy;
begin
  { Closing the ring cancels all pending requests. }
  if FRingFd >= 0 then
  begin
    fpclose(FRingFd);
    FRingFd := -1;
  end;
  if FWakeupFd >= 0 then
  begin
    fpclose(FWakeupFd);
    FWakeupFd := -1;
  end;
  if FSQRingPtr <> nil then
    fpmunmap(FSQRingPtr, FSQRingSize);
  if Pointer(FSQEs) <> nil then
    fpmunmap(Pointer(FSQEs), FSQEsSize);
  if FCQRingPtr <> nil then
    fpmunmap(FCQRingPtr, FCQRingSize);
  FSQRingPtr := nil;
  FSQEs := nil;
  FCQRingPtr := nil;
  inherited Destroy;
  FreeAndNil(FSubmitLock);
end;

function TIOUringEventLoop.EventsToPollMask(AEvents: TEventLoopEvents): cuint16;
begin
  Result := 0;
  if eleRead in AEvents then
    Result := Result or POLLIN_CONST or POLLPRI_CONST;
  if eleWrite in AEvents then
    Result := Result or POLLOUT_CONST;
end;

function TIOUringEventLoop.PollMaskToEvents(AMask: cint32): TEventLoopEvents;
begin
  Result := [];
  if (AMask and (POLLIN_CONST or POLLPRI_CONST)) <> 0 then
    Include(Result, eleRead);
  if (AMask and POLLOUT_CONST) <> 0 then
    Include(Result, eleWrite);
  if (AMask and POLLERR_CONST) <> 0 then
    Include(Result, eleError);
  if (AMask and POLLHUP_CONST) <> 0 then
    Include(Result, eleHangup);
end;

procedure TIOUringEventLoop.EnsureHandleSlot(AHandle: TLoopHandle);
var
  LOld, LNew, I: Integer;
begin
  if AHandle < Length(FPollGen) then
    Exit;
  LOld := Length(FPollGen);
  LNew := LOld;
  if LNew < 64 then
    LNew := 64;
  while LNew <= AHandle do
    LNew := LNew * 2;
  SetLength(FPollGen, LNew);
  SetLength(FPollMask, LNew);
  SetLength(FPollArmed, LNew);
  for I := LOld to LNew - 1 do
  begin
    FPollGen[I] := 0;
    FPollMask[I] := 0;
    FPollArmed[I] := False;
  end;
end;

function TIOUringEventLoop.PollUserData(AHandle: TLoopHandle): cuint64;
begin
  Result := (cuint64(FPollGen[AHandle]) shl 32) or cuint64(cuint32(AHandle));
end;

procedure TIOUringEventLoop.QueueSQE(constref ASQE: Tio_uring_sqe);
var
  LTail, LIndex: cuint32;
begin
  { Called with FSubmitLock held. Make room if the ring is full. }
  if FSQTail^ - LoadAcquire(FSQHead) >= FSQEntries then
    SubmitPending;
  LTail := FSQTail^;
  LIndex := LTail and FSQRingMask;
  FSQEs[LIndex] := ASQE;
  (FSQArray + LIndex)^ := LIndex;
  { The kernel must see the entry before the new tail. }
  WriteBarrier;
  FSQTail^ := LTail + 1;
end;

procedure TIOUringEventLoop.SubmitPending;
var
  LToSubmit: cuint32;
  LRes: TSysResult;
begin
  { Called with FSubmitLock held. }
  repeat
    LToSubmit := FSQTail^ - LoadAcquire(FSQHead);
    if LToSubmit = 0 then
      Exit;
    LRes := Do_SysCall(syscall_nr_io_uring_enter, FRingFd, LToSubmit, 0, 0, 0);
    if (LRes < 0) and (fpgeterrno <> ESysEINTR) and (fpgeterrno <> ESysEAGAIN) and (fpgeterrno <> ESysEBUSY) then
      Exit;
  until LRes >= LToSubmit;
end;

procedure TIOUringEventLoop.QueuePollAdd(AHandle: TLoopHandle);
var
  LSqe: Tio_uring_sqe;
begin
  if (FPollMask[AHandle] = 0) or FPollArmed[AHandle] then
    Exit;
  FillChar(LSqe, SizeOf(LSqe), 0);
  LSqe.opcode := IORING_OP_POLL_ADD;
  LSqe.fd := AHandle;
  LSqe.rw_flags := FPollMask[AHandle];
  LSqe.user_data := PollUserData(AHandle);
  QueueSQE(LSqe);
  FPollArmed[AHandle] := True;
end;

procedure TIOUringEventLoop.QueuePollRemove(AHandle: TLoopHandle);
var
  LSqe: Tio_uring_sqe;
begin
  if not FPollArmed[AHandle] then
    Exit;
  FillChar(LSqe, SizeOf(LSqe), 0);
  LSqe.opcode := IORING_OP_POLL_REMOVE;
  LSqe.fd := -1;
  LSqe.addr := PollUserData(AHandle);
  LSqe.user_data := UD_POLL_REMOVE;
  QueueSQE(LSqe);
  FPollArmed[AHandle] := False;
end;

procedure TIOUringEventLoop.QueueWakeupPoll;
var
  LSqe: Tio_uring_sqe;
begin
  FillChar(LSqe, SizeOf(LSqe), 0);
  LSqe.opcode := IORING_OP_POLL_ADD;
  LSqe.fd := FWakeupFd;
  LSqe.rw_flags := POLLIN_CONST;
  LSqe.user_data := UD_WAKEUP;
  QueueSQE(LSqe);
end;

procedure TIOUringEventLoop.DoRegisterHandle(AHandle: TLoopHandle; AEvents: TEventLoopEvents; const ACallback: TAsyncIOCompletion; AUserData: Pointer);
begin
  if AHandle < 0 then
    raise EEventLoopException.CreateFmt('Invalid handle %d', [AHandle]);
  FSubmitLock.Acquire;
  try
    EnsureHandleSlot(AHandle);
    QueuePollRemove(AHandle);
    Inc(FPollGen[AHandle]);
    FPollMask[AHandle] := EventsToPollMask(AEvents);
    QueuePollAdd(AHandle);
    SubmitPending;
  finally
    FSubmitLock.Release;
  end;
end;

procedure TIOUringEventLoop.DoModifyHandle(AHandle: TLoopHandle; AEvents: TEventLoopEvents);
var
  LMask: cuint16;
begin
  if AHandle < 0 then
    Exit;
  LMask := EventsToPollMask(AEvents);
  FSubmitLock.Acquire;
  try
    EnsureHandleSlot(AHandle);
    if (LMask = FPollMask[AHandle]) and (FPollArmed[AHandle] or (LMask = 0)) then
      Exit;
    QueuePollRemove(AHandle);
    Inc(FPollGen[AHandle]);
    FPollMask[AHandle] := LMask;
    QueuePollAdd(AHandle);
    SubmitPending;
  finally
    FSubmitLock.Release;
  end;
end;

procedure TIOUringEventLoop.DoUnregisterHandle(AHandle: TLoopHandle);
begin
  if AHandle < 0 then
    Exit;
  FSubmitLock.Acquire;
  try
    if AHandle >= Length(FPollGen) then
      Exit;
    QueuePollRemove(AHandle);
    Inc(FPollGen[AHandle]);
    FPollMask[AHandle] := 0;
    SubmitPending;
  finally
    FSubmitLock.Release;
  end;
end;

procedure TIOUringEventLoop.DoWakeup;
var
  LVal: QWord;
begin
  if FWakeupFd >= 0 then
  begin
    LVal := 1;
    fpwrite(FWakeupFd, LVal, SizeOf(LVal));
  end;
end;

procedure TIOUringEventLoop.DoPoll(ATimeoutMs: Integer);
var
  LHead, LTail: cuint32;
  LCqe: Tio_uring_cqe;
  LFd: cint;
  LGen: cuint32;
  LVal: QWord;
  LSqe: Tio_uring_sqe;
  LCurrent: Boolean;
  LMinComplete: cuint32;
  LFlags: cuint32;
begin
  FSubmitLock.Acquire;
  try
    if ATimeoutMs > 0 then
    begin
      { The timeout completes after ATimeoutMs or as soon as one other
        request completes (off = 1), so it never outlives this call. }
      FTimeout.tv_sec := ATimeoutMs div 1000;
      FTimeout.tv_nsec := cint64(ATimeoutMs mod 1000) * 1000000;
      FillChar(LSqe, SizeOf(LSqe), 0);
      LSqe.opcode := IORING_OP_TIMEOUT;
      LSqe.fd := -1;
      LSqe.addr := cuint64(PtrUInt(@FTimeout));
      LSqe.len := 1;
      LSqe.off := 1;
      LSqe.user_data := UD_TIMEOUT;
      QueueSQE(LSqe);
    end;
    SubmitPending;
  finally
    FSubmitLock.Release;
  end;

  { Wait outside the lock so that other threads can submit meanwhile. }
  LHead := FCQHead^;
  LTail := LoadAcquire(FCQTail);
  if (LHead = LTail) and (ATimeoutMs <> 0) then
  begin
    LMinComplete := 1;
    LFlags := IORING_ENTER_GETEVENTS;
    Do_SysCall(syscall_nr_io_uring_enter, FRingFd, 0, LMinComplete, LFlags, 0);
  end;

  while True do
  begin
    LHead := FCQHead^;
    LTail := LoadAcquire(FCQTail);
    if LHead = LTail then
      Break;
    { Entries up to the tail are valid once the tail has been read. }
    ReadBarrier;
    LCqe := FCQEs[LHead and FCQRingMask];
    { Release the slot before running callbacks, which may submit. }
    WriteBarrier;
    FCQHead^ := LHead + 1;

    if LCqe.user_data = UD_WAKEUP then
    begin
      fpread(FWakeupFd, LVal, SizeOf(LVal));
      FSubmitLock.Acquire;
      try
        QueueWakeupPoll;
      finally
        FSubmitLock.Release;
      end;
    end
    else if (LCqe.user_data and UD_KIND_MASK) = UD_SPECIAL then
      { timeout or poll-remove completion: nothing to do }
    else
    begin
      LFd := cint(cuint32(LCqe.user_data and $FFFFFFFF));
      LGen := cuint32(LCqe.user_data shr 32);
      FSubmitLock.Acquire;
      try
        LCurrent := (LFd < Length(FPollGen)) and (FPollGen[LFd] = LGen);
        if LCurrent then
          FPollArmed[LFd] := False;
      finally
        FSubmitLock.Release;
      end;
      { A stale completion (handle removed or re-registered since) or a
        cancelled request is dropped and never re-armed. }
      if LCurrent and (LCqe.res >= 0) then
      begin
        TriggerHandle(LFd, PollMaskToEvents(LCqe.res));
        FSubmitLock.Acquire;
        try
          if (LFd < Length(FPollGen)) and (FPollGen[LFd] = LGen) then
            QueuePollAdd(LFd);
        finally
          FSubmitLock.Release;
        end;
      end;
    end;
  end;

  FSubmitLock.Acquire;
  try
    SubmitPending;
  finally
    FSubmitLock.Release;
  end;
end;

{$endif}

end.
