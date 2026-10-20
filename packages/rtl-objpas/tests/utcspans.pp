unit utcspans;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}
{$codepage utf8}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, spans;

type
  TIntSpan = specialize TSpan<LongInt>;
  TReadOnlyIntSpan = specialize TReadOnlySpan<LongInt>;
  TStrSpan = specialize TSpan<String>;
  TReadOnlyStrSpan = specialize TReadOnlySpan<String>;

  TTestSpanCreate = class(TTestCase)
  published
    procedure TestStaticArray;
    procedure TestDynamicArrayWritesThrough;
    procedure TestBytes;
    procedure TestArrayRange;
    procedure TestArrayRangeOutOfBounds;
    procedure TestEmptyArray;
    procedure TestRawPointer;
    procedure TestNegativeLength;
  end;

  TTestSpanAccess = class(TTestCase)
  published
    procedure TestReadWrite;
    procedure TestIndexBelowZero;
    procedure TestIndexAtLength;
    procedure TestReadOnlyIndexChecked;
    procedure TestImplicitReadOnly;
    procedure TestEnumerator;
    procedure TestEnumeratorEmpty;
  end;

  TTestSpanSlice = class(TTestCase)
  published
    procedure TestSlice;
    procedure TestSliceToEnd;
    procedure TestEmptySliceAtEnd;
    procedure TestSliceOutOfRange;
    procedure TestNestedSlices;
  end;

  TTestSpanChunk = class(TTestCase)
  published
    procedure TestChunksCoverWithoutOverlap;
    procedure TestInvalidChunk;
  end;

  TTestSpanOps = class(TTestCase)
  published
    procedure TestCopyFrom;
    procedure TestCopyFromTooLong;
    procedure TestCopyFromOverlapping;
    procedure TestCopyFromManaged;
    procedure TestFill;
    procedure TestToArrayIsCopy;
    procedure TestOverlaps;
    procedure TestAnsiStringSpan;
    procedure TestUnicodeStringSpan;
    procedure TestMutableSpanMakesUnique;
    procedure TestEmptyStringSpan;
  end;

  TTestSpanParallel = class(TTestCase)
  published
    procedure TestParallelFillChunks;
    procedure TestParallelSumChunks;
  end;

implementation

function Seq(ACount: Integer): TIntSpan.TElementArray;
var
  I: Integer;
begin
  Result := nil;
  SetLength(Result, ACount);
  for I := 0 to ACount - 1 do
    Result[I] := I;
end;

{ Asserts that AProc raises ERangeError. }
type
  TSpanProc = procedure of object;

procedure AssertRangeError(const AMsg: string; AProc: TSpanProc);
var
  Raised: Boolean;
begin
  Raised := False;
  try
    AProc();
  except
    on ERangeError do
      Raised := True;
  end;
  TAssert.AssertTrue(AMsg, Raised);
end;

{ helpers whose methods are used with AssertRangeError }
type
  TProbe = class
    Arr: TIntSpan.TElementArray;
    Span: TIntSpan;
    RO: TReadOnlyIntSpan;
    Dummy: LongInt;
    procedure ReadBelowZero;
    procedure ReadAtLength;
    procedure WriteAtLength;
    procedure ReadOnlyAtLength;
    procedure CreateRangeTooLong;
    procedure CreateRangeNegativeStart;
    procedure CreateRangeHugeCount;
    procedure CreateNegativeLength;
    procedure SliceTooLong;
    procedure SliceNegative;
    procedure SliceStartPastEnd;
    procedure SliceHuge;
    procedure ChunkZeroCount;
    procedure ChunkNegativeIndex;
    procedure ChunkIndexTooBig;
    procedure CopyTooLong;
  end;

procedure TProbe.ReadBelowZero;
begin
  Dummy := Span[-1];
end;

procedure TProbe.ReadAtLength;
begin
  Dummy := Span[Span.Length];
end;

procedure TProbe.WriteAtLength;
begin
  Span[Span.Length] := 1;
end;

procedure TProbe.ReadOnlyAtLength;
begin
  Dummy := RO[RO.Length];
end;

procedure TProbe.CreateRangeTooLong;
begin
  Span := TIntSpan.Create(Arr, 2, Length(Arr) - 1);
end;

procedure TProbe.CreateRangeNegativeStart;
begin
  Span := TIntSpan.Create(Arr, -1, 1);
end;

procedure TProbe.CreateRangeHugeCount;
begin
  { start + count would overflow }
  Span := TIntSpan.Create(Arr, 1, High(SizeInt));
end;

procedure TProbe.CreateNegativeLength;
begin
  Span := TIntSpan.Create(@Dummy, -1);
end;

procedure TProbe.SliceTooLong;
begin
  Span := Span.Slice(1, Span.Length);
end;

procedure TProbe.SliceNegative;
begin
  Span := Span.Slice(0, -1);
end;

procedure TProbe.SliceStartPastEnd;
begin
  Span := Span.Slice(Span.Length + 1);
end;

procedure TProbe.SliceHuge;
begin
  Span := Span.Slice(High(SizeInt), High(SizeInt));
end;

procedure TProbe.ChunkZeroCount;
begin
  Span := Span.Chunk(0, 0);
end;

procedure TProbe.ChunkNegativeIndex;
begin
  Span := Span.Chunk(-1, 4);
end;

procedure TProbe.ChunkIndexTooBig;
begin
  Span := Span.Chunk(4, 4);
end;

procedure TProbe.CopyTooLong;
begin
  Span.Slice(0, 2).CopyFrom(Span);
end;

{ TTestSpanCreate }

procedure TTestSpanCreate.TestStaticArray;
var
  A: array[1..5] of LongInt = (10, 20, 30, 40, 50);
  S: TIntSpan;
begin
  S := TIntSpan.Create(A);
  AssertEquals('length', 5, S.Length);
  AssertEquals('first', 10, S[0]);
  AssertEquals('last', 50, S[4]);
  S[2] := 33;
  AssertEquals('write through', 33, A[3]);
end;

procedure TTestSpanCreate.TestDynamicArrayWritesThrough;
var
  A: TIntSpan.TElementArray;
  S: TIntSpan;
begin
  A := Seq(10);
  S := TIntSpan.Create(A);
  AssertTrue('no copy: same memory', S.Data = @A[0]);
  S[9] := 99;
  AssertEquals('write through', 99, A[9]);
end;

procedure TTestSpanCreate.TestBytes;
var
  B: TBytes;
  S: TByteSpan;
begin
  B := TEncoding.ASCII.GetBytes('abc');
  S := TByteSpan.Create(B);
  AssertEquals('length', 3, S.Length);
  AssertEquals('b', Ord('b'), S[1]);
end;

procedure TTestSpanCreate.TestArrayRange;
var
  A: TIntSpan.TElementArray;
  S: TIntSpan;
begin
  A := Seq(10);
  S := TIntSpan.Create(A, 3, 4);
  AssertEquals('length', 4, S.Length);
  AssertEquals('first', 3, S[0]);
  AssertEquals('last', 6, S[3]);
  S := TIntSpan.Create(A, 10, 0);
  AssertTrue('empty at end', S.IsEmpty);
end;

procedure TTestSpanCreate.TestArrayRangeOutOfBounds;
var
  P: TProbe;
begin
  P := TProbe.Create;
  try
    P.Arr := Seq(5);
    AssertRangeError('too long', @P.CreateRangeTooLong);
    AssertRangeError('negative start', @P.CreateRangeNegativeStart);
    AssertRangeError('overflowing count', @P.CreateRangeHugeCount);
  finally
    P.Free;
  end;
end;

procedure TTestSpanCreate.TestEmptyArray;
var
  A: TIntSpan.TElementArray;
  S: TIntSpan;
  R: TReadOnlyIntSpan;
  X: LongInt;
  N: Integer;
begin
  A := nil;
  S := TIntSpan.Create(A);
  R := TReadOnlyIntSpan.Create(A);
  AssertTrue('empty', S.IsEmpty and R.IsEmpty);
  AssertNull('no data', S.Data);
  N := 0;
  for X in S do
    Inc(N);
  AssertEquals('no iterations', 0, N);
end;

procedure TTestSpanCreate.TestRawPointer;
var
  A: array[0..3] of LongInt = (1, 2, 3, 4);
  S: TReadOnlyIntSpan;
begin
  S := TReadOnlyIntSpan.Create(@A[1], 2);
  AssertEquals('length', 2, S.Length);
  AssertEquals('item', 3, S[1]);
end;

procedure TTestSpanCreate.TestNegativeLength;
var
  P: TProbe;
begin
  P := TProbe.Create;
  try
    AssertRangeError('negative length', @P.CreateNegativeLength);
  finally
    P.Free;
  end;
end;

{ TTestSpanAccess }

procedure TTestSpanAccess.TestReadWrite;
var
  A: TIntSpan.TElementArray;
  S: TIntSpan;
  I: Integer;
begin
  A := Seq(8);
  S := TIntSpan.Create(A);
  for I := 0 to S.Length - 1 do
    S[I] := S[I] * 2;
  for I := 0 to 7 do
    AssertEquals('doubled', I * 2, A[I]);
end;

procedure TTestSpanAccess.TestIndexBelowZero;
var
  P: TProbe;
begin
  P := TProbe.Create;
  try
    P.Arr := Seq(4);
    P.Span := TIntSpan.Create(P.Arr);
    AssertRangeError('index -1', @P.ReadBelowZero);
  finally
    P.Free;
  end;
end;

procedure TTestSpanAccess.TestIndexAtLength;
var
  P: TProbe;
begin
  P := TProbe.Create;
  try
    P.Arr := Seq(4);
    P.Span := TIntSpan.Create(P.Arr);
    AssertRangeError('read at length', @P.ReadAtLength);
    AssertRangeError('write at length', @P.WriteAtLength);
    AssertEquals('nothing written past the end', 3, P.Arr[3]);
  finally
    P.Free;
  end;
end;

procedure TTestSpanAccess.TestReadOnlyIndexChecked;
var
  P: TProbe;
begin
  P := TProbe.Create;
  try
    P.Arr := Seq(4);
    P.RO := TReadOnlyIntSpan.Create(P.Arr);
    AssertRangeError('read-only at length', @P.ReadOnlyAtLength);
  finally
    P.Free;
  end;
end;

function SumRO(const S: TReadOnlyIntSpan): Int64;
var
  X: LongInt;
begin
  Result := 0;
  for X in S do
    Inc(Result, X);
end;

procedure TTestSpanAccess.TestImplicitReadOnly;
var
  A: TIntSpan.TElementArray;
  S: TIntSpan;
  R: TReadOnlyIntSpan;
begin
  A := Seq(5);
  S := TIntSpan.Create(A);
  R := S;
  AssertEquals('same length', S.Length, R.Length);
  AssertTrue('same data', R.Data = S.Data);
  { a TSpan can be passed where a TReadOnlySpan is expected }
  AssertEquals('sum', 10, SumRO(S));
  AssertEquals('AsReadOnly', 10, SumRO(S.AsReadOnly));
end;

procedure TTestSpanAccess.TestEnumerator;
var
  A: TIntSpan.TElementArray;
  X: LongInt;
  N, Sum: Integer;
begin
  A := Seq(100);
  N := 0;
  Sum := 0;
  for X in TIntSpan.Create(A).Slice(10, 20) do
  begin
    Inc(N);
    Inc(Sum, X);
  end;
  AssertEquals('count', 20, N);
  AssertEquals('sum 10..29', 390, Sum);
end;

procedure TTestSpanAccess.TestEnumeratorEmpty;
var
  A: TIntSpan.TElementArray;
  X: LongInt;
  N: Integer;
begin
  A := Seq(3);
  N := 0;
  for X in TIntSpan.Create(A).Slice(3) do
    Inc(N);
  AssertEquals('no iterations', 0, N);
end;

{ TTestSpanSlice }

procedure TTestSpanSlice.TestSlice;
var
  A: TIntSpan.TElementArray;
  S: TIntSpan;
begin
  A := Seq(10);
  S := TIntSpan.Create(A).Slice(2, 3);
  AssertEquals('length', 3, S.Length);
  AssertEquals('first', 2, S[0]);
  S[0] := -2;
  AssertEquals('write through', -2, A[2]);
end;

procedure TTestSpanSlice.TestSliceToEnd;
var
  A: TIntSpan.TElementArray;
  S: TIntSpan;
begin
  A := Seq(10);
  S := TIntSpan.Create(A).Slice(7);
  AssertEquals('length', 3, S.Length);
  AssertEquals('last', 9, S[2]);
end;

procedure TTestSpanSlice.TestEmptySliceAtEnd;
var
  A: TIntSpan.TElementArray;
begin
  A := Seq(4);
  AssertTrue('empty', TIntSpan.Create(A).Slice(4).IsEmpty);
  AssertTrue('empty with count', TIntSpan.Create(A).Slice(4, 0).IsEmpty);
end;

procedure TTestSpanSlice.TestSliceOutOfRange;
var
  P: TProbe;
begin
  P := TProbe.Create;
  try
    P.Arr := Seq(6);
    P.Span := TIntSpan.Create(P.Arr);
    AssertRangeError('too long', @P.SliceTooLong);
    AssertRangeError('negative count', @P.SliceNegative);
    AssertRangeError('start past end', @P.SliceStartPastEnd);
    AssertRangeError('overflowing', @P.SliceHuge);
  finally
    P.Free;
  end;
end;

procedure TTestSpanSlice.TestNestedSlices;
var
  A: TIntSpan.TElementArray;
  S: TIntSpan;
begin
  A := Seq(100);
  S := TIntSpan.Create(A).Slice(10, 50).Slice(5, 10).Slice(2);
  AssertEquals('length', 8, S.Length);
  AssertEquals('first', 17, S[0]);
end;

{ TTestSpanChunk }

procedure TTestSpanChunk.TestChunksCoverWithoutOverlap;
var
  A: TIntSpan.TElementArray;
  Hits: array of Integer;
  S, C, Prev: TIntSpan;
  Len, Count, I, J, MinLen, MaxLen: Integer;
begin
  for Len := 0 to 40 do
    for Count := 1 to 12 do
    begin
      A := Seq(Len);
      S := TIntSpan.Create(A);
      Hits := nil;
      SetLength(Hits, Len);
      MinLen := MaxInt;
      MaxLen := -1;
      Prev := S.Slice(0, 0);
      for I := 0 to Count - 1 do
      begin
        C := S.Chunk(I, Count);
        { chunks are consecutive }
        AssertTrue(Format('chunk %d/%d of %d follows the previous', [I, Count, Len]),
          C.Data = Prev.Data + Prev.Length);
        AssertFalse('no overlap with the previous chunk', C.Overlaps(Prev));
        for J := 0 to C.Length - 1 do
          Inc(Hits[C[J]]);
        if C.Length < MinLen then
          MinLen := C.Length;
        if C.Length > MaxLen then
          MaxLen := C.Length;
        Prev := C;
      end;
      for J := 0 to Len - 1 do
        AssertEquals(Format('element %d of %d in exactly one of %d chunks', [J, Len, Count]), 1, Hits[J]);
      AssertTrue('sizes differ by at most one', MaxLen - MinLen <= 1);
    end;
end;

procedure TTestSpanChunk.TestInvalidChunk;
var
  P: TProbe;
begin
  P := TProbe.Create;
  try
    P.Arr := Seq(8);
    P.Span := TIntSpan.Create(P.Arr);
    AssertRangeError('zero count', @P.ChunkZeroCount);
    AssertRangeError('negative index', @P.ChunkNegativeIndex);
    AssertRangeError('index = count', @P.ChunkIndexTooBig);
  finally
    P.Free;
  end;
end;

{ TTestSpanOps }

procedure TTestSpanOps.TestCopyFrom;
var
  A, B: TIntSpan.TElementArray;
begin
  A := Seq(5);
  B := nil;
  SetLength(B, 8);
  TIntSpan.Create(B).Slice(2).CopyFrom(TIntSpan.Create(A));
  AssertEquals('before', 0, B[1]);
  AssertEquals('first copied', 0, B[2]);
  AssertEquals('last copied', 4, B[6]);
  AssertEquals('after', 0, B[7]);
end;

procedure TTestSpanOps.TestCopyFromTooLong;
var
  P: TProbe;
begin
  P := TProbe.Create;
  try
    P.Arr := Seq(4);
    P.Span := TIntSpan.Create(P.Arr);
    AssertRangeError('source longer than destination', @P.CopyTooLong);
    AssertEquals('destination unchanged', 1, P.Arr[1]);
  finally
    P.Free;
  end;
end;

procedure TTestSpanOps.TestCopyFromOverlapping;
var
  A: TIntSpan.TElementArray;
  S: TIntSpan;
  I: Integer;
begin
  { destination after the source: must copy backwards }
  A := Seq(10);
  S := TIntSpan.Create(A);
  S.Slice(2).CopyFrom(S.Slice(0, 8));
  for I := 2 to 9 do
    AssertEquals('shift right', I - 2, A[I]);
  { destination before the source }
  A := Seq(10);
  S := TIntSpan.Create(A);
  S.CopyFrom(S.Slice(3));
  for I := 0 to 6 do
    AssertEquals('shift left', I + 3, A[I]);
end;

procedure TTestSpanOps.TestCopyFromManaged;
var
  Src, Dst: TStrSpan.TElementArray;
  I: Integer;
begin
  Src := nil;
  Dst := nil;
  SetLength(Src, 4);
  SetLength(Dst, 4);
  for I := 0 to 3 do
  begin
    Src[I] := 'item' + IntToStr(I);
    Dst[I] := 'old' + IntToStr(I);
  end;
  TStrSpan.Create(Dst).CopyFrom(TStrSpan.Create(Src));
  for I := 0 to 3 do
    AssertEquals('copied', 'item' + IntToStr(I), Dst[I]);
  { the strings are shared (assignment), not duplicated bytewise }
  AssertTrue('shared', Pointer(Dst[0]) = Pointer(Src[0]));
  Src := nil;
  AssertEquals('still valid after the source is gone', 'item2', Dst[2]);
  { overlapping copy of managed elements }
  TStrSpan.Create(Dst).Slice(1).CopyFrom(TStrSpan.Create(Dst).Slice(0, 3));
  AssertEquals('shifted', 'item0', Dst[1]);
  AssertEquals('shifted last', 'item2', Dst[3]);
end;

procedure TTestSpanOps.TestFill;
var
  A: TIntSpan.TElementArray;
begin
  A := Seq(6);
  TIntSpan.Create(A).Slice(1, 3).Fill(7);
  AssertEquals('before', 0, A[0]);
  AssertEquals('filled', 7, A[2]);
  AssertEquals('after', 4, A[4]);
end;

procedure TTestSpanOps.TestToArrayIsCopy;
var
  A, B: TIntSpan.TElementArray;
begin
  A := Seq(5);
  B := TIntSpan.Create(A).Slice(1, 3).ToArray;
  AssertEquals('length', 3, Length(B));
  B[0] := 100;
  AssertEquals('source untouched', 1, A[1]);
  AssertEquals('read-only ToArray', 3, Length(TReadOnlyIntSpan.Create(A).Slice(2).ToArray));
end;

procedure TTestSpanOps.TestOverlaps;
var
  A, B: TIntSpan.TElementArray;
  S: TIntSpan;
begin
  A := Seq(10);
  B := Seq(10);
  S := TIntSpan.Create(A);
  AssertTrue('same', S.Overlaps(S));
  AssertTrue('partial', S.Slice(0, 5).Overlaps(S.Slice(4, 2)));
  AssertFalse('adjacent', S.Slice(0, 5).Overlaps(S.Slice(5)));
  AssertFalse('other array', S.Overlaps(TIntSpan.Create(B)));
  AssertFalse('empty', S.Overlaps(S.Slice(3, 0)));
end;

procedure TTestSpanOps.TestAnsiStringSpan;
var
  S, T: AnsiString;
  R: TReadOnlyAnsiCharSpan;
begin
  S := 'Hello, span';
  R := SpanOf(S);
  AssertEquals('length', Length(S), R.Length);
  AssertEquals('char', 'H', R[0]);
  SetString(T, R.Slice(7).Data, R.Slice(7).Length);
  AssertEquals('slice', 'span', T);
end;

procedure TTestSpanOps.TestUnicodeStringSpan;
var
  S: UnicodeString;
  R: TReadOnlyWideCharSpan;
begin
  S := 'Привіт';
  R := SpanOf(S);
  AssertEquals('length', 6, R.Length);
  AssertTrue('char', R[0] = WideChar($041F));
end;

procedure TTestSpanOps.TestMutableSpanMakesUnique;
var
  A, B: AnsiString;
  M: TAnsiCharSpan;
begin
  A := 'abcdef';
  UniqueString(A);
  B := A;
  M := MutableSpanOf(A);
  M[0] := 'X';
  AssertEquals('modified', 'Xbcdef', A);
  AssertEquals('other reference unchanged', 'abcdef', B);
end;

procedure TTestSpanOps.TestEmptyStringSpan;
var
  S: AnsiString;
  U: UnicodeString;
begin
  S := '';
  U := '';
  AssertTrue('ansi', SpanOf(S).IsEmpty);
  AssertTrue('unicode', SpanOf(U).IsEmpty);
  AssertTrue('mutable', MutableSpanOf(S).IsEmpty);
end;

{ TTestSpanParallel }

const
  ParallelThreads = 8;
  ParallelLength = 1000003;

type
  PFillJob = ^TFillJob;
  TFillJob = record
    Span: TIntSpan;
    Value: LongInt;
    Sum: Int64;
  end;

function FillWorker(P: Pointer): PtrInt;
var
  Job: PFillJob absolute P;
  I: SizeInt;
begin
  { every thread writes only its own chunk }
  for I := 0 to Job^.Span.Length - 1 do
    Job^.Span[I] := Job^.Value;
  Result := 0;
end;

function SumWorker(P: Pointer): PtrInt;
var
  Job: PFillJob absolute P;
  X: LongInt;
begin
  Job^.Sum := 0;
  for X in Job^.Span do
    Inc(Job^.Sum, X);
  Result := 0;
end;

procedure RunJobs(var Jobs: array of TFillJob; AWorker: TThreadFunc);
var
  Ids: array[0..ParallelThreads - 1] of TThreadID;
  I: Integer;
begin
  for I := 0 to High(Jobs) do
    Ids[I] := BeginThread(AWorker, @Jobs[I]);
  for I := 0 to High(Jobs) do
  begin
    WaitForThreadTerminate(Ids[I], 0);
    CloseThread(Ids[I]);
  end;
end;

procedure TTestSpanParallel.TestParallelFillChunks;
var
  A: TIntSpan.TElementArray;
  Whole: TIntSpan;
  Jobs: array[0..ParallelThreads - 1] of TFillJob;
  I, J: Integer;
  Start: SizeInt;
begin
  A := nil;
  SetLength(A, ParallelLength);
  Whole := TIntSpan.Create(A);
  for I := 0 to ParallelThreads - 1 do
  begin
    Jobs[I].Span := Whole.Chunk(I, ParallelThreads);
    Jobs[I].Value := I + 1;
    for J := 0 to I - 1 do
      AssertFalse('chunks do not overlap', Jobs[I].Span.Overlaps(Jobs[J].Span));
  end;
  RunJobs(Jobs, @FillWorker);
  Start := 0;
  for I := 0 to ParallelThreads - 1 do
  begin
    for J := 0 to Jobs[I].Span.Length - 1 do
      if A[Start + J] <> I + 1 then
        Fail(Format('element %d written by the wrong thread', [Start + J]));
    Inc(Start, Jobs[I].Span.Length);
  end;
  AssertEquals('all elements written', ParallelLength, Start);
end;

procedure TTestSpanParallel.TestParallelSumChunks;
var
  A: TIntSpan.TElementArray;
  Whole: TIntSpan;
  Jobs: array[0..ParallelThreads - 1] of TFillJob;
  I: Integer;
  Total: Int64;
begin
  A := Seq(ParallelLength);
  Whole := TIntSpan.Create(A);
  for I := 0 to ParallelThreads - 1 do
    Jobs[I].Span := Whole.Chunk(I, ParallelThreads);
  RunJobs(Jobs, @SumWorker);
  Total := 0;
  for I := 0 to ParallelThreads - 1 do
    Inc(Total, Jobs[I].Sum);
  AssertEquals('sum 0..n-1', Int64(ParallelLength) * (ParallelLength - 1) div 2, Total);
end;

initialization
  RegisterTests([TTestSpanCreate, TTestSpanAccess, TTestSpanSlice, TTestSpanChunk,
    TTestSpanOps, TTestSpanParallel]);
end.
