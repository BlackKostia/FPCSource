unit utcsmartptrs;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}
{$modeswitch implicitfunctionspecialization}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, smartptrs;

type
  { Counts its own construction and destruction. }
  TTracked = class
  public
    Value: Integer;
    Magic: LongWord;
    constructor Create(AValue: Integer = 0);
    destructor Destroy; override;
  end;

  TScopedTracked = specialize TScoped<TTracked>;
  TArcTracked = specialize TArc<TTracked>;
  TWeakTracked = specialize TWeak<TTracked>;

  TTestScoped = class(TTestCase)
  protected
    procedure SetUp; override;
  published
    procedure TestEmptyByDefault;
    procedure TestFreesOnScopeExit;
    procedure TestFreesOnException;
    procedure TestCreateOverExistingFreesOld;
    procedure TestResetFreesPrevious;
    procedure TestResetSameObjectIsNoop;
    procedure TestResetNil;
    procedure TestRelease;
    procedure TestMove;
    procedure TestSelfMove;
    procedure TestSwap;
    procedure TestCopyOwningRaises;
    procedure TestCopyEmptyIsAllowed;
    procedure TestValueParamRaises;
    procedure TestConstParamAllowed;
    procedure TestRecordCopyRaises;
    procedure TestDynArrayCopyRaises;
    procedure TestFieldOfClass;
    procedure TestStringList;
    procedure TestMakeScoped;
    procedure TestMakeScopedOverExistingFreesOld;
  end;

  TTestArc = class(TTestCase)
  protected
    procedure SetUp; override;
  published
    procedure TestEmptyByDefault;
    procedure TestFreesOnScopeExit;
    procedure TestCopiesShareObject;
    procedure TestValueParamCounts;
    procedure TestFunctionResult;
    procedure TestSelfAssignment;
    procedure TestCreateOverExistingReleasesOld;
    procedure TestResetSameObjectIsNoop;
    procedure TestReset;
    procedure TestEquality;
    procedure TestDynArray;
    procedure TestFreesOnException;
    procedure TestMakeArc;
    procedure TestMakeArcOverExistingReleasesOld;
  end;

  TTestWeak = class(TTestCase)
  protected
    procedure SetUp; override;
  published
    procedure TestEmptyIsExpired;
    procedure TestLockWhileAlive;
    procedure TestExpiresWithLastOwner;
    procedure TestWeakDoesNotKeepAlive;
    procedure TestCopyAndReset;
    procedure TestBreaksCycle;
  end;

  TTestArcStress = class(TTestCase)
  protected
    procedure SetUp; override;
  published
    procedure TestConcurrentCopies;
    procedure TestConcurrentLastRelease;
    procedure TestLockRacesWithRelease;
  end;

implementation

const
  AliveMagic = $A11FE;
  StressThreads = 8;

var
  Created: LongInt = 0;
  Destroyed: LongInt = 0;

procedure ResetCounters;
begin
  Created := 0;
  Destroyed := 0;
end;

constructor TTracked.Create(AValue: Integer);
begin
  inherited Create;
  Value := AValue;
  Magic := AliveMagic;
  InterlockedIncrement(Created);
end;

destructor TTracked.Destroy;
begin
  Magic := 0;
  InterlockedIncrement(Destroyed);
  inherited Destroy;
end;

{ TTestScoped }

procedure TTestScoped.SetUp;
begin
  ResetCounters;
end;

procedure TTestScoped.TestEmptyByDefault;
var
  S: TScopedTracked;
begin
  AssertFalse('empty', S.IsAssigned);
  AssertNull('nil object', S.Obj);
end;

procedure ScopedLocal;
var
  S: TScopedTracked;
begin
  S.Reset(TTracked.Create(1));
  S.Obj.Value := 2;
end;

procedure TTestScoped.TestFreesOnScopeExit;
begin
  ScopedLocal;
  AssertEquals('created', 1, Created);
  AssertEquals('destroyed', 1, Destroyed);
end;

procedure ScopedRaise;
var
  S: TScopedTracked;
begin
  S := TScopedTracked.Create(TTracked.Create);
  raise EAbort.Create('boom');
end;

procedure TTestScoped.TestFreesOnException;
begin
  try
    ScopedRaise;
    Fail('exception expected');
  except
    on EAbort do ;
  end;
  AssertEquals('destroyed despite exception', 1, Destroyed);
end;

procedure TTestScoped.TestCreateOverExistingFreesOld;
var
  S: TScopedTracked;
begin
  S := TScopedTracked.Create(TTracked.Create(1));
  S := TScopedTracked.Create(TTracked.Create(2));
  AssertEquals('old freed', 1, Destroyed);
  AssertEquals('new kept', 2, S.Obj.Value);
end;

procedure TTestScoped.TestResetFreesPrevious;
var
  S: TScopedTracked;
begin
  S.Reset(TTracked.Create(1));
  S.Reset(TTracked.Create(2));
  AssertEquals('old freed', 1, Destroyed);
  AssertEquals('new kept', 2, S.Get.Value);
end;

procedure TTestScoped.TestResetSameObjectIsNoop;
var
  S: TScopedTracked;
  O: TTracked;
begin
  O := TTracked.Create;
  S.Reset(O);
  S.Reset(O);
  AssertEquals('not freed', 0, Destroyed);
  AssertSame('same', O, S.Obj);
end;

procedure TTestScoped.TestResetNil;
var
  S: TScopedTracked;
begin
  S.Reset(TTracked.Create);
  S.Reset;
  AssertEquals('freed', 1, Destroyed);
  AssertFalse('empty', S.IsAssigned);
end;

function ScopedRelease: TTracked;
var
  S: TScopedTracked;
begin
  S.Reset(TTracked.Create(7));
  Result := S.Release;
end;

procedure TTestScoped.TestRelease;
var
  O: TTracked;
begin
  O := ScopedRelease;
  try
    AssertEquals('not freed by scope', 0, Destroyed);
    AssertEquals('value', 7, O.Value);
  finally
    O.Free;
  end;
end;

procedure TTestScoped.TestMove;
var
  A, B: TScopedTracked;
  O: TTracked;
begin
  O := TTracked.Create;
  A.Reset(O);
  B.Reset(TTracked.Create);
  B := A.Move;
  AssertFalse('source empty', A.IsAssigned);
  AssertSame('target owns', O, B.Obj);
  AssertEquals('previous target object freed', 1, Destroyed);
end;

procedure TTestScoped.TestSelfMove;
var
  A: TScopedTracked;
  O: TTracked;
begin
  O := TTracked.Create;
  A.Reset(O);
  A := A.Move;
  AssertSame('still owns', O, A.Obj);
  AssertEquals('not freed', 0, Destroyed);
end;

procedure TTestScoped.TestSwap;
var
  A, B: TScopedTracked;
begin
  A.Reset(TTracked.Create(1));
  B.Reset(TTracked.Create(2));
  A.Swap(B);
  AssertEquals('A', 2, A.Obj.Value);
  AssertEquals('B', 1, B.Obj.Value);
  AssertEquals('nothing freed', 0, Destroyed);
end;

procedure TTestScoped.TestCopyOwningRaises;
var
  A, B: TScopedTracked;
  Raised: Boolean;
begin
  A.Reset(TTracked.Create(1));
  B.Reset(TTracked.Create(2));
  Raised := False;
  try
    B := A;
  except
    on ESmartPtrError do
      Raised := True;
  end;
  AssertTrue('ESmartPtrError', Raised);
  AssertEquals('A untouched', 1, A.Obj.Value);
  AssertEquals('B untouched', 2, B.Obj.Value);
  AssertEquals('nothing freed', 0, Destroyed);
end;

procedure TTestScoped.TestCopyEmptyIsAllowed;
var
  A, B: TScopedTracked;
begin
  B.Reset(TTracked.Create);
  B := A;
  AssertFalse('B empty', B.IsAssigned);
  AssertEquals('B object freed', 1, Destroyed);
end;

procedure TakeScopedByValue(S: TScopedTracked);
begin
  S.Obj.Value := -1;
end;

function ReadScopedConst(const S: TScopedTracked): Integer;
begin
  Result := S.Obj.Value;
end;

procedure TTestScoped.TestValueParamRaises;
var
  A: TScopedTracked;
  Raised: Boolean;
begin
  A.Reset(TTracked.Create(5));
  Raised := False;
  try
    TakeScopedByValue(A);
  except
    on ESmartPtrError do
      Raised := True;
  end;
  AssertTrue('ESmartPtrError', Raised);
  AssertEquals('still owned', 5, A.Obj.Value);
  AssertEquals('nothing freed', 0, Destroyed);
end;

procedure TTestScoped.TestConstParamAllowed;
var
  A: TScopedTracked;
begin
  A.Reset(TTracked.Create(5));
  AssertEquals('value', 5, ReadScopedConst(A));
  AssertEquals('nothing freed', 0, Destroyed);
end;

type
  TScopedPair = record
    Name: string;
    Item: TScopedTracked;
  end;

procedure TTestScoped.TestRecordCopyRaises;
var
  A, B: TScopedPair;
  Raised: Boolean;
begin
  A.Name := 'a';
  A.Item.Reset(TTracked.Create(1));
  Raised := False;
  try
    B := A;
  except
    on ESmartPtrError do
      Raised := True;
  end;
  AssertTrue('ESmartPtrError', Raised);
  AssertEquals('A still owns', 1, A.Item.Obj.Value);
  A.Item.Reset;
  B.Item.Reset;
  AssertEquals('freed exactly once', 1, Destroyed);
end;

procedure TTestScoped.TestDynArrayCopyRaises;
var
  A, B: array of TScopedTracked;
  Raised: Boolean;
begin
  SetLength(A, 2);
  A[0].Reset(TTracked.Create);
  Raised := False;
  try
    B := Copy(A);
  except
    on ESmartPtrError do
      Raised := True;
  end;
  AssertTrue('ESmartPtrError', Raised);
  B := nil;
  AssertTrue('A still owns', A[0].IsAssigned);
  A := nil;
  AssertEquals('freed exactly once', 1, Destroyed);
end;

type
  THolder = class
    Item: TScopedTracked;
  end;

procedure TTestScoped.TestFieldOfClass;
var
  H: THolder;
begin
  H := THolder.Create;
  H.Item.Reset(TTracked.Create);
  H.Free;
  AssertEquals('field freed with owner', 1, Destroyed);
end;

procedure TTestScoped.TestStringList;
var
  L: specialize TScoped<TStringList>;
begin
  L.Reset(TStringList.Create);
  L.Obj.Add('b');
  L.Obj.Add('a');
  L.Obj.Sort;
  AssertEquals('first', 'a', L.Obj[0]);
  AssertEquals('second', 'b', L.Obj[1]);
end;

procedure TTestScoped.TestMakeScoped;
var
  S: TScopedTracked;
  L: specialize TScoped<TStringList>;
begin
  { explicit and inferred specialization }
  S := specialize MakeScoped<TTracked>(TTracked.Create(3));
  AssertEquals('explicit', 3, S.Obj.Value);
  L := MakeScoped(TStringList.Create);
  L.Obj.Add('x');
  AssertEquals('inferred', 1, L.Obj.Count);
  S.Reset;
  AssertEquals('freed', 1, Destroyed);
end;

procedure TTestScoped.TestMakeScopedOverExistingFreesOld;
var
  S: TScopedTracked;
begin
  S := MakeScoped(TTracked.Create(1));
  S := MakeScoped(TTracked.Create(2));
  AssertEquals('old freed', 1, Destroyed);
  AssertEquals('new kept', 2, S.Obj.Value);
end;

{ TTestArc }

procedure TTestArc.SetUp;
begin
  ResetCounters;
end;

procedure TTestArc.TestEmptyByDefault;
var
  A: TArcTracked;
begin
  AssertFalse('empty', A.IsAssigned);
  AssertNull('nil object', A.Obj);
  AssertEquals('use count', 0, A.UseCount);
end;

procedure ArcLocal;
var
  A: TArcTracked;
begin
  A := TArcTracked.Create(TTracked.Create);
end;

procedure TTestArc.TestFreesOnScopeExit;
begin
  ArcLocal;
  AssertEquals('destroyed', 1, Destroyed);
end;

procedure TTestArc.TestCopiesShareObject;
var
  A, B, C: TArcTracked;
begin
  A := TArcTracked.Create(TTracked.Create(3));
  B := A;
  C := B;
  AssertEquals('use count', 3, A.UseCount);
  AssertSame('shared', A.Obj, C.Obj);
  A.Reset;
  B.Reset;
  AssertEquals('alive while C holds it', 0, Destroyed);
  AssertEquals('value', 3, C.Obj.Value);
  C.Reset;
  AssertEquals('freed with last owner', 1, Destroyed);
end;

function UseCountByValue(A: TArcTracked): LongInt;
begin
  Result := A.UseCount;
end;

procedure TTestArc.TestValueParamCounts;
var
  A: TArcTracked;
begin
  A := TArcTracked.Create(TTracked.Create);
  AssertEquals('inside callee', 2, UseCountByValue(A));
  AssertEquals('after call', 1, A.UseCount);
end;

type
  TArcOwner = class
    Shared: TArcTracked;
    function GetShared: TArcTracked;
  end;

function TArcOwner.GetShared: TArcTracked;
begin
  Result := Shared;
end;

procedure TTestArc.TestFunctionResult;
var
  Owner: TArcOwner;
  A: TArcTracked;
begin
  Owner := TArcOwner.Create;
  try
    Owner.Shared := TArcTracked.Create(TTracked.Create);
    A := Owner.GetShared;
    AssertEquals('two owners', 2, A.UseCount);
  finally
    Owner.Free;
  end;
  AssertEquals('alive after owner freed', 0, Destroyed);
  A.Reset;
  AssertEquals('freed', 1, Destroyed);
end;

procedure TTestArc.TestSelfAssignment;
var
  A: TArcTracked;
begin
  A := TArcTracked.Create(TTracked.Create);
  A := A;
  AssertEquals('use count', 1, A.UseCount);
  AssertEquals('not freed', 0, Destroyed);
end;

procedure TTestArc.TestCreateOverExistingReleasesOld;
var
  A: TArcTracked;
begin
  A := TArcTracked.Create(TTracked.Create(1));
  A := TArcTracked.Create(TTracked.Create(2));
  AssertEquals('old freed', 1, Destroyed);
  AssertEquals('new', 2, A.Obj.Value);
  AssertEquals('use count', 1, A.UseCount);
end;

procedure TTestArc.TestResetSameObjectIsNoop;
var
  A: TArcTracked;
begin
  A := TArcTracked.Create(TTracked.Create);
  A.Reset(A.Obj);
  AssertEquals('not freed', 0, Destroyed);
  AssertEquals('use count', 1, A.UseCount);
end;

procedure TTestArc.TestReset;
var
  A, B: TArcTracked;
begin
  A := TArcTracked.Create(TTracked.Create(1));
  B := A;
  A.Reset(TTracked.Create(2));
  AssertEquals('B keeps first', 1, B.Obj.Value);
  AssertEquals('A owns second', 2, A.Obj.Value);
  AssertEquals('counts', 1, B.UseCount);
  B.Reset;
  AssertEquals('first freed', 1, Destroyed);
end;

procedure TTestArc.TestEquality;
var
  A, B, C, E1, E2: TArcTracked;
begin
  A := TArcTracked.Create(TTracked.Create);
  B := A;
  C := TArcTracked.Create(TTracked.Create);
  AssertTrue('same object', A = B);
  AssertTrue('different objects', A <> C);
  AssertTrue('empty equal', E1 = E2);
  AssertFalse('empty vs assigned', E1 = A);
end;

procedure TTestArc.TestDynArray;
var
  Arr, Arr2: array of TArcTracked;
  I: Integer;
  A: TArcTracked;
begin
  A := TArcTracked.Create(TTracked.Create);
  SetLength(Arr, 10);
  for I := 0 to High(Arr) do
    Arr[I] := A;
  AssertEquals('11 owners', 11, A.UseCount);
  Arr2 := Copy(Arr);
  AssertEquals('21 owners', 21, A.UseCount);
  Arr := nil;
  Arr2 := nil;
  AssertEquals('back to one', 1, A.UseCount);
  A.Reset;
  AssertEquals('freed', 1, Destroyed);
end;

procedure ArcRaise(const Src: TArcTracked);
var
  A: TArcTracked;
begin
  A := Src;
  raise EAbort.Create('boom');
end;

procedure TTestArc.TestFreesOnException;
var
  A: TArcTracked;
begin
  A := TArcTracked.Create(TTracked.Create);
  try
    ArcRaise(A);
  except
    on EAbort do ;
  end;
  AssertEquals('local copy released', 1, A.UseCount);
end;

procedure TTestArc.TestMakeArc;
var
  A, B: TArcTracked;
begin
  A := specialize MakeArc<TTracked>(TTracked.Create(5));
  B := MakeArc(TTracked.Create(6));
  AssertEquals('explicit', 5, A.Obj.Value);
  AssertEquals('inferred', 6, B.Obj.Value);
  AssertEquals('one owner', 1, B.UseCount);
  A.Reset;
  B.Reset;
  AssertEquals('both freed', 2, Destroyed);
end;

procedure TTestArc.TestMakeArcOverExistingReleasesOld;
var
  A, Keep: TArcTracked;
begin
  A := MakeArc(TTracked.Create(1));
  Keep := A;
  A := MakeArc(TTracked.Create(2));
  AssertEquals('old kept alive by Keep', 0, Destroyed);
  AssertEquals('Keep is sole owner', 1, Keep.UseCount);
  Keep.Reset;
  AssertEquals('old freed', 1, Destroyed);
  AssertEquals('new', 2, A.Obj.Value);
end;

{ TTestWeak }

procedure TTestWeak.SetUp;
begin
  ResetCounters;
end;

procedure TTestWeak.TestEmptyIsExpired;
var
  W: TWeakTracked;
begin
  AssertTrue('expired', W.Expired);
  AssertFalse('lock empty', W.Lock.IsAssigned);
end;

procedure TTestWeak.TestLockWhileAlive;
var
  A, L: TArcTracked;
  W: TWeakTracked;
begin
  A := TArcTracked.Create(TTracked.Create(9));
  W := TWeakTracked.Create(A);
  AssertEquals('weak does not count', 1, A.UseCount);
  AssertFalse('alive', W.Expired);
  AssertTrue('try lock', W.TryLock(L));
  AssertEquals('locked value', 9, L.Obj.Value);
  AssertEquals('two owners', 2, A.UseCount);
end;

procedure TTestWeak.TestExpiresWithLastOwner;
var
  A, L: TArcTracked;
  W: TWeakTracked;
begin
  A := TArcTracked.Create(TTracked.Create);
  W.Assign(A);
  A.Reset;
  AssertEquals('freed', 1, Destroyed);
  AssertTrue('expired', W.Expired);
  AssertFalse('try lock', W.TryLock(L));
  AssertFalse('lock empty', L.IsAssigned);
end;

{ Temporaries of managed types returned by functions live until the end of
  the routine that created them, so the temporary owner is created here. }
function WeakOfTemporary: TWeakTracked;
var
  A: TArcTracked;
begin
  A := TArcTracked.Create(TTracked.Create);
  Result := TWeakTracked.Create(A);
end;

procedure TTestWeak.TestWeakDoesNotKeepAlive;
var
  W: TWeakTracked;
begin
  W := WeakOfTemporary;
  AssertEquals('owner gone', 1, Destroyed);
  AssertTrue('expired', W.Expired);
end;

procedure TTestWeak.TestCopyAndReset;
var
  A, L: TArcTracked;
  W1, W2: TWeakTracked;
begin
  A := TArcTracked.Create(TTracked.Create(4));
  W1 := TWeakTracked.Create(A);
  W2 := W1;
  W1.Reset;
  AssertTrue('reset is expired', W1.Expired);
  L := W2.Lock;
  AssertEquals('copy still works', 4, L.Obj.Value);
  L.Reset;
  A.Reset;
  AssertTrue('copy expired', W2.Expired);
end;

type
  TNode = class;
  TNodeArc = specialize TArc<TNode>;
  TNodeWeak = specialize TWeak<TNode>;

  TNode = class(TTracked)
    Parent: TNodeWeak;
    Children: array of TNodeArc;
  end;

procedure TTestWeak.TestBreaksCycle;
var
  Root, Child, P: TNodeArc;
  I: Integer;
begin
  Root := TNodeArc.Create(TNode.Create(0));
  for I := 1 to 3 do
  begin
    Child := TNodeArc.Create(TNode.Create(I));
    Child.Obj.Parent.Assign(Root);
    SetLength(Root.Obj.Children, I);
    Root.Obj.Children[I - 1] := Child;
  end;
  P := Child.Obj.Parent.Lock;
  AssertEquals('parent reachable', 0, P.Obj.Value);
  P.Reset;
  Child.Reset;
  Root.Reset;
  AssertEquals('whole tree freed', 4, Destroyed);
end;

{ TTestArcStress

  Raw RTL threads (BeginThread/WaitForThreadTerminate): TThread.WaitFor
  polls in the main thread, which makes many short rounds slow. }

type
  PCopyJob = ^TCopyJob;
  TCopyJob = record
    Arc: TArcTracked;
    Iterations: Integer;
    Failed: Boolean;
  end;

function CopyWorker(P: Pointer): PtrInt;
var
  Job: PCopyJob absolute P;
  I: Integer;
  Local, Local2: TArcTracked;
begin
  for I := 1 to Job^.Iterations do
  begin
    Local := Job^.Arc;
    Local2 := Local;
    if Local2.Obj.Magic <> AliveMagic then
      Job^.Failed := True;
    Local.Reset;
    Local2.Reset;
  end;
  { Drop the job's own reference: the last thread to get here frees the
    object if the main thread has already let go. }
  Job^.Arc.Reset;
  Result := 0;
end;

type
  TCopyJobs = array[1..StressThreads] of TCopyJob;

procedure StartCopyJobs(var Jobs: TCopyJobs; var Ids: array of TThreadID;
  constref A: TArcTracked; Iterations: Integer);
var
  I: Integer;
begin
  for I := 1 to StressThreads do
  begin
    Jobs[I].Arc := A;
    Jobs[I].Iterations := Iterations;
    Jobs[I].Failed := False;
    Ids[I - 1] := BeginThread(@CopyWorker, @Jobs[I]);
  end;
end;

procedure TTestArcStress.SetUp;
begin
  ResetCounters;
end;

procedure TTestArcStress.TestConcurrentCopies;
var
  A: TArcTracked;
  Jobs: TCopyJobs;
  Ids: array[1..StressThreads] of TThreadID;
  I: Integer;
begin
  A := TArcTracked.Create(TTracked.Create);
  StartCopyJobs(Jobs, Ids, A, 200000);
  for I := 1 to StressThreads do
  begin
    WaitForThreadTerminate(Ids[I], 0);
    CloseThread(Ids[I]);
    AssertFalse('object alive while referenced', Jobs[I].Failed);
  end;
  AssertEquals('only main owner left', 1, A.UseCount);
  A.Reset;
  AssertEquals('freed once', 1, Destroyed);
end;

procedure TTestArcStress.TestConcurrentLastRelease;
const
  Rounds = 500;
var
  Round, I: Integer;
  A: TArcTracked;
  Jobs: TCopyJobs;
  Ids: array[1..StressThreads] of TThreadID;
begin
  for Round := 1 to Rounds do
  begin
    A := TArcTracked.Create(TTracked.Create);
    StartCopyJobs(Jobs, Ids, A, 100);
    { The main thread drops its reference while the workers run: one of
      them performs the final release. }
    A.Reset;
    for I := 1 to StressThreads do
    begin
      WaitForThreadTerminate(Ids[I], 0);
      CloseThread(Ids[I]);
      AssertFalse('object alive while referenced', Jobs[I].Failed);
    end;
    AssertEquals('freed exactly once', Round, Destroyed);
  end;
  AssertEquals('created', Rounds, Created);
end;

type
  PLockJob = ^TLockJob;
  TLockJob = record
    Weak: TWeakTracked;
    Failed: Boolean;
  end;

function LockWorker(P: Pointer): PtrInt;
var
  Job: PLockJob absolute P;
  L: TArcTracked;
begin
  while Job^.Weak.TryLock(L) do
  begin
    { A successfully locked object must never be destroyed under us. }
    if L.Obj.Magic <> AliveMagic then
      Job^.Failed := True;
    L.Reset;
  end;
  Job^.Weak.Reset;
  Result := 0;
end;

procedure TTestArcStress.TestLockRacesWithRelease;
const
  Rounds = 500;
  Lockers = 4;
var
  Round, I: Integer;
  A: TArcTracked;
  Jobs: array[1..Lockers] of TLockJob;
  Ids: array[1..Lockers] of TThreadID;
begin
  for Round := 1 to Rounds do
  begin
    A := TArcTracked.Create(TTracked.Create);
    for I := 1 to Lockers do
    begin
      Jobs[I].Weak.Assign(A);
      Jobs[I].Failed := False;
      Ids[I] := BeginThread(@LockWorker, @Jobs[I]);
    end;
    { Let the lockers spin for a moment, then drop the only owner. }
    ThreadSwitch;
    A.Reset;
    for I := 1 to Lockers do
    begin
      WaitForThreadTerminate(Ids[I], 0);
      CloseThread(Ids[I]);
      AssertFalse('locked object stayed alive', Jobs[I].Failed);
    end;
    AssertEquals('freed exactly once', Round, Destroyed);
  end;
end;

initialization
  RegisterTests([TTestScoped, TTestArc, TTestWeak, TTestArcStress]);
end.
