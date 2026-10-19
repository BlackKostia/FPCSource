{
    This file is part of the Free Pascal run time library.
    Copyright (c) 2026 by the Free Pascal development team

    Smart pointers built on management operators of advanced records:

      TScoped<T> - unique ownership (std::unique_ptr): the object is freed
                   when the variable goes out of scope, also on exceptions.
      TArc<T>    - atomic reference counted shared ownership (std::shared_ptr,
                   Rust Arc) for any TObject descendant.
      TWeak<T>   - non-owning reference to an object held by TArc<T>
                   (std::weak_ptr, Rust Weak), breaks reference cycles.

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

 **********************************************************************}
{$IFNDEF FPC_DOTTEDUNITS}
unit smartptrs;
{$ENDIF FPC_DOTTEDUNITS}

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

{$IFDEF FPC_DOTTEDUNITS}
uses System.SysUtils;
{$ELSE FPC_DOTTEDUNITS}
uses sysutils;
{$ENDIF FPC_DOTTEDUNITS}

type
  { Raised when a TScoped<T> that owns an object is copied. }
  ESmartPtrError = class(EInvalidOpException);

  { TScoped<T>

    Sole owner of an object. The object is freed when the record is finalized
    (end of the scope of a local variable, destruction of the owning class or
    record), including unwinding caused by an exception.

    Ownership cannot be duplicated: assigning or passing by value an owning
    TScoped raises ESmartPtrError. Pass it as const/var/constref and transfer
    ownership explicitly with Move, Release or Reset. }

  generic TScoped<T: class> = record
  private
    FObj: T;
  public
    class operator Initialize(var A: TScoped);
    class operator Finalize(var A: TScoped);
    class operator AddRef(var A: TScoped);
    class operator Copy(constref Src: TScoped; var Dst: TScoped);
    { Takes ownership of AObj. Whatever the destination owned before is freed. }
    class function Create(AObj: T): TScoped; static;
    { Frees the owned object and takes ownership of AObj (nil = just free). }
    procedure Reset(AObj: T = nil);
    { Gives up ownership without freeing; the caller becomes responsible. }
    function Release: T;
    { Transfers ownership to the result: B := A.Move. A becomes empty. }
    function Move: TScoped;
    procedure Swap(var Other: TScoped);
    function IsAssigned: Boolean; inline;
    function Get: T; inline;
    property Obj: T read FObj;
  end;

  { Control block shared by all TArc<T>/TWeak<T> of one object.
    Strong counts TArc owners; Weak counts TWeak references plus one
    reference held collectively by all strong owners. The object is freed
    when Strong drops to zero, the block itself when Weak drops to zero. }

  PArcBlock = ^TArcBlock;
  TArcBlock = record
    Strong: LongInt;
    Weak: LongInt;
    Obj: TObject;
  end;

  { TArc<T>

    Atomically reference counted shared ownership of any object; the class
    does not have to descend from TInterfacedObject. Copies of TArc may be
    created and destroyed concurrently in different threads. A single TArc
    variable is not itself thread-safe: concurrent writes to the same
    variable (or a write concurrent with a read) must be synchronized,
    exactly as with std::shared_ptr. The owned object is not protected
    either: TArc only manages its lifetime. }

  generic TArc<T: class> = record
  private
    FBlock: PArcBlock;
    function GetObj: T; inline;
  public
    class operator Initialize(var A: TArc);
    class operator Finalize(var A: TArc);
    class operator AddRef(var A: TArc);
    class operator Copy(constref Src: TArc; var Dst: TArc);
    class operator =(constref A, B: TArc): Boolean; inline;
    class operator <>(constref A, B: TArc): Boolean; inline;
    { Takes ownership of AObj and starts reference counting it. AObj must
      not be owned by anything else, including another TArc. }
    class function Create(AObj: T): TArc; static;
    { Drops this reference and, if AObj <> nil, starts owning AObj. }
    procedure Reset(AObj: T = nil);
    function IsAssigned: Boolean; inline;
    function Get: T; inline;
    { Number of TArc owners; a snapshot, useful for diagnostics and tests. }
    function UseCount: LongInt;
    property Obj: T read GetObj;
  end;

  { TWeak<T>

    Observes an object owned by TArc<T> without keeping it alive. Lock
    returns a TArc that owns the object, or an empty TArc if all owners
    are already gone. Use it to break reference cycles (parent <-> child,
    observer lists, caches). The same thread-safety rules as TArc apply. }

  generic TWeak<T: class> = record
  public type
    TArcT = specialize TArc<T>;
  private
    FBlock: PArcBlock;
  public
    class operator Initialize(var A: TWeak);
    class operator Finalize(var A: TWeak);
    class operator AddRef(var A: TWeak);
    class operator Copy(constref Src: TWeak; var Dst: TWeak);
    class function Create(constref A: TArcT): TWeak; static;
    procedure Assign(constref A: TArcT);
    procedure Reset;
    { Atomically upgrades to a strong reference (empty if expired). }
    function Lock: TArcT;
    function TryLock(out A: TArcT): Boolean;
    function Expired: Boolean; inline;
  end;

{ Implementation helpers. They are in the interface only because the
  generic code above is specialized in other units; do not call directly. }
procedure ScopedCopyError;
function ArcBlockNew(AObj: TObject): PArcBlock;
procedure ArcStrongAcquire(ABlock: PArcBlock); inline;
function ArcStrongTryAcquire(ABlock: PArcBlock): Boolean;
procedure ArcStrongRelease(ABlock: PArcBlock);
procedure ArcWeakAcquire(ABlock: PArcBlock); inline;
procedure ArcWeakRelease(ABlock: PArcBlock);

implementation

resourcestring
  SScopedCopy = 'TScoped<T> owns its object exclusively and cannot be copied; '
    + 'pass it as const/var and transfer ownership with Move, Release or Reset';

{ Helpers }

procedure ScopedCopyError;
begin
  raise ESmartPtrError.Create(SScopedCopy);
end;

function ArcBlockNew(AObj: TObject): PArcBlock;
begin
  try
    New(Result);
  except
    { The caller handed over ownership: do not leak the object. }
    AObj.Free;
    raise;
  end;
  Result^.Strong := 1;
  Result^.Weak := 1;
  Result^.Obj := AObj;
end;

procedure ArcStrongAcquire(ABlock: PArcBlock);
begin
  InterlockedIncrement(ABlock^.Strong);
end;

function ArcStrongTryAcquire(ABlock: PArcBlock): Boolean;
var
  N: LongInt;
begin
  { Never resurrect an object whose last owner is gone: increment only
    from a non-zero value. }
  repeat
    N := ABlock^.Strong;
    if N <= 0 then
      Exit(False);
  until InterlockedCompareExchange(ABlock^.Strong, N + 1, N) = N;
  Result := True;
end;

procedure ArcStrongRelease(ABlock: PArcBlock);
begin
  if InterlockedDecrement(ABlock^.Strong) = 0 then
    try
      ABlock^.Obj.Free;
    finally
      ABlock^.Obj := nil;
      ArcWeakRelease(ABlock);
    end;
end;

procedure ArcWeakAcquire(ABlock: PArcBlock);
begin
  InterlockedIncrement(ABlock^.Weak);
end;

procedure ArcWeakRelease(ABlock: PArcBlock);
begin
  if InterlockedDecrement(ABlock^.Weak) = 0 then
    Dispose(ABlock);
end;

{ TScoped }

class operator TScoped.Initialize(var A: TScoped);
begin
  A.FObj := nil;
end;

class operator TScoped.Finalize(var A: TScoped);
var
  O: TObject;
begin
  O := A.FObj;
  A.FObj := nil;
  O.Free;
end;

class operator TScoped.AddRef(var A: TScoped);
begin
  { A is a bitwise copy made by the compiler (value parameter, copy of a
    dynamic array or of a containing record). It must not own the object,
    otherwise both copies would free it. }
  if A.FObj <> nil then
  begin
    A.FObj := nil;
    ScopedCopyError;
  end;
end;

class operator TScoped.Copy(constref Src: TScoped; var Dst: TScoped);
begin
  if @Src = @Dst then
    Exit;
  if Src.FObj <> nil then
    ScopedCopyError;
  Dst.Reset(nil);
end;

class function TScoped.Create(AObj: T): TScoped;
begin
  { Result may be the destination variable itself, still holding its old
    object: Reset frees it. }
  Result.Reset(AObj);
end;

procedure TScoped.Reset(AObj: T);
var
  Old: TObject;
begin
  Old := FObj;
  if Old = TObject(AObj) then
    Exit;
  FObj := AObj;
  Old.Free;
end;

function TScoped.Release: T;
begin
  Result := FObj;
  FObj := nil;
end;

function TScoped.Move: TScoped;
begin
  { Release first: Result may alias Self. }
  Result.Reset(Release);
end;

procedure TScoped.Swap(var Other: TScoped);
var
  O: T;
begin
  O := FObj;
  FObj := Other.FObj;
  Other.FObj := O;
end;

function TScoped.IsAssigned: Boolean;
begin
  Result := FObj <> nil;
end;

function TScoped.Get: T;
begin
  Result := FObj;
end;

{ TArc }

class operator TArc.Initialize(var A: TArc);
begin
  A.FBlock := nil;
end;

class operator TArc.Finalize(var A: TArc);
var
  B: PArcBlock;
begin
  B := A.FBlock;
  A.FBlock := nil;
  if B <> nil then
    ArcStrongRelease(B);
end;

class operator TArc.AddRef(var A: TArc);
begin
  if A.FBlock <> nil then
    ArcStrongAcquire(A.FBlock);
end;

class operator TArc.Copy(constref Src: TArc; var Dst: TArc);
var
  Old: PArcBlock;
begin
  { Acquire before release: handles self-assignment and aliasing. }
  if Src.FBlock <> nil then
    ArcStrongAcquire(Src.FBlock);
  Old := Dst.FBlock;
  Dst.FBlock := Src.FBlock;
  if Old <> nil then
    ArcStrongRelease(Old);
end;

class operator TArc.=(constref A, B: TArc): Boolean;
begin
  Result := A.GetObj = B.GetObj;
end;

class operator TArc.<>(constref A, B: TArc): Boolean;
begin
  Result := A.GetObj <> B.GetObj;
end;

class function TArc.Create(AObj: T): TArc;
begin
  { Result may be the destination variable itself, still holding its old
    reference: Reset releases it. }
  Result.Reset(AObj);
end;

procedure TArc.Reset(AObj: T);
var
  Old, NewBlock: PArcBlock;
begin
  Old := FBlock;
  if (Old <> nil) and (Old^.Obj = TObject(AObj)) then
    Exit;
  if AObj <> nil then
    NewBlock := ArcBlockNew(AObj)
  else
    NewBlock := nil;
  FBlock := NewBlock;
  if Old <> nil then
    ArcStrongRelease(Old);
end;

function TArc.GetObj: T;
begin
  if FBlock <> nil then
    Result := T(FBlock^.Obj)
  else
    Result := nil;
end;

function TArc.IsAssigned: Boolean;
begin
  Result := FBlock <> nil;
end;

function TArc.Get: T;
begin
  Result := GetObj;
end;

function TArc.UseCount: LongInt;
begin
  if FBlock <> nil then
    Result := FBlock^.Strong
  else
    Result := 0;
end;

{ TWeak }

class operator TWeak.Initialize(var A: TWeak);
begin
  A.FBlock := nil;
end;

class operator TWeak.Finalize(var A: TWeak);
var
  B: PArcBlock;
begin
  B := A.FBlock;
  A.FBlock := nil;
  if B <> nil then
    ArcWeakRelease(B);
end;

class operator TWeak.AddRef(var A: TWeak);
begin
  if A.FBlock <> nil then
    ArcWeakAcquire(A.FBlock);
end;

class operator TWeak.Copy(constref Src: TWeak; var Dst: TWeak);
var
  Old: PArcBlock;
begin
  if Src.FBlock <> nil then
    ArcWeakAcquire(Src.FBlock);
  Old := Dst.FBlock;
  Dst.FBlock := Src.FBlock;
  if Old <> nil then
    ArcWeakRelease(Old);
end;

class function TWeak.Create(constref A: TArcT): TWeak;
begin
  Result.Assign(A);
end;

procedure TWeak.Assign(constref A: TArcT);
var
  Old: PArcBlock;
begin
  if A.FBlock <> nil then
    ArcWeakAcquire(A.FBlock);
  Old := FBlock;
  FBlock := A.FBlock;
  if Old <> nil then
    ArcWeakRelease(Old);
end;

procedure TWeak.Reset;
var
  B: PArcBlock;
begin
  B := FBlock;
  FBlock := nil;
  if B <> nil then
    ArcWeakRelease(B);
end;

{ A managed Result is always initialized by the caller; here it may even be
  the destination variable that already holds a reference. }
{$push}{$warn 5093 off}
function TWeak.Lock: TArcT;
var
  B, Old: PArcBlock;
begin
  B := FBlock;
  if (B <> nil) and not ArcStrongTryAcquire(B) then
    B := nil;
  Old := Result.FBlock;
  Result.FBlock := B;
  if Old <> nil then
    ArcStrongRelease(Old);
end;
{$pop}

function TWeak.TryLock(out A: TArcT): Boolean;
begin
  A := Lock;
  Result := A.IsAssigned;
end;

function TWeak.Expired: Boolean;
begin
  Result := (FBlock = nil) or (FBlock^.Strong <= 0);
end;

end.
