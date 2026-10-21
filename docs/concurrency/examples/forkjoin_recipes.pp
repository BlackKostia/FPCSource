{ Recipes for System.Threading.ForkJoin, each checked against a sequential
  computation. See docs/concurrency/guides/forkjoin-recipes.md }
program forkjoin_recipes;

{$mode objfpc}{$H+}
{$modeswitch arrowfunctions}
{$modeswitch inlinevars}
{$modeswitch interpolation}
{$modeswitch using}
{$modeswitch tuples}

uses
  {$ifdef unix}cthreads,{$endif}
  SysUtils, StrUtils, Math, System.Threading.ForkJoin;

procedure Check(aOk: Boolean; const aWhat: string);
begin
  if aOk then
    WriteLn($'  ok    {aWhat}')
  else
  begin
    WriteLn($'  FAIL  {aWhat}');
    ExitCode := 1;
  end;
end;

{ 1. Image: every row on its own }

procedure Brighten(aPixels: PByte; aWidth, aHeight, aDelta: Integer);
begin
  TForkJoin.Each(0, aHeight - 1, Y =>
    begin
      var Row := aPixels + Y * aWidth;
      for var X := 0 to aWidth - 1 do
        Row[X] := Min(255, Row[X] + aDelta);
    end);
end;

procedure RecipeImage;
const
  W = 1920;
  H = 1080;
var
  Img, Ref: array of Byte;
begin
  SetLength(Img, W * H);
  for var I := 0 to High(Img) do
    Img[I] := Byte(I * 7);
  Ref := Copy(Img);
  for var I := 0 to High(Ref) do
    Ref[I] := Min(255, Ref[I] + 40);
  Brighten(PByte(Img), W, H, 40);
  Check(CompareMem(@Img[0], @Ref[0], Length(Img)), '1. image rows');
end;

{ 2. Histogram: a local histogram per chunk, merged once per chunk }

type
  THistogram = array[0..255] of Int64;

function ParallelHistogram(const aData: TBytes): THistogram;
const
  CHUNKS = 64;
var
  Total: THistogram;
begin
  FillChar(Total, SizeOf(Total), 0);
  var Data := aData;
  var Len := Length(Data);
  TForkJoin.Each(0, CHUNKS - 1, C =>
    begin
      var Local: THistogram;
      FillChar(Local, SizeOf(Local), 0);
      for var I := C * Len div CHUNKS to (C + 1) * Len div CHUNKS - 1 do
        Inc(Local[Data[I]]);
      for var B := 0 to 255 do
        if Local[B] <> 0 then
          InterlockedExchangeAdd64(Total[B], Local[B]);
    end, 1);
  Result := Total;
end;

procedure RecipeHistogram;
var
  Data: TBytes;
  Ref: THistogram;
begin
  SetLength(Data, 10000000);
  for var I := 0 to High(Data) do
    Data[I] := Byte((I * 2654435761) shr 24);
  FillChar(Ref, SizeOf(Ref), 0);
  for var B in Data do
    Inc(Ref[B]);
  var Hist := ParallelHistogram(Data);
  Check(CompareMem(@Hist, @Ref, SizeOf(Ref)), '2. histogram with local counters');
end;

{ 3. Quicksort: the two partitions in parallel }

procedure SequentialQuickSort(A: PInt64; Lo, Hi: Integer);
begin
  while Lo < Hi do
  begin
    var Pivot := A[(Lo + Hi) div 2];
    var I := Lo;
    var J := Hi;
    while I <= J do
    begin
      while A[I] < Pivot do Inc(I);
      while A[J] > Pivot do Dec(J);
      if I <= J then
      begin
        (A[I], A[J]) := (A[J], A[I]);
        Inc(I);
        Dec(J);
      end;
    end;
    if J - Lo < Hi - I then
    begin
      SequentialQuickSort(A, Lo, J);
      Lo := I;
    end
    else
    begin
      SequentialQuickSort(A, I, Hi);
      Hi := J;
    end;
  end;
end;

procedure ParallelQuickSort(A: PInt64; Lo, Hi: Integer);
begin
  if Hi - Lo < 20000 then
  begin
    SequentialQuickSort(A, Lo, Hi);
    Exit;
  end;
  var Pivot := A[(Lo + Hi) div 2];
  var I := Lo;
  var J := Hi;
  while I <= J do
  begin
    while A[I] < Pivot do Inc(I);
    while A[J] > Pivot do Dec(J);
    if I <= J then
    begin
      (A[I], A[J]) := (A[J], A[I]);
      Inc(I);
      Dec(J);
    end;
  end;
  TForkJoin.Join(() => ParallelQuickSort(A, Lo, J),
                 () => ParallelQuickSort(A, I, Hi));
end;

procedure RecipeQuickSort;
var
  A: array of Int64;
begin
  SetLength(A, 5000000);
  var Seed: UInt64 := 42;
  for var I := 0 to High(A) do
  begin
    Seed := Seed * 6364136223846793005 + 1442695040888963407;
    A[I] := Int64(Seed shr 16);
  end;
  ParallelQuickSort(PInt64(A), 0, High(A));
  var Sorted := True;
  for var I := 1 to High(A) do
    if A[I - 1] > A[I] then
      Sorted := False;
  Check(Sorted, '3. parallel quicksort');
end;

{ 4. Tree: the children of a node in one group, recursively }

type
  PNode = ^TNode;
  TNode = record
    Size: Int64;
    Children: array of PNode;
  end;

function BuildTree(aDepth, aFanOut: Integer; var aCount: Int64): PNode;
begin
  New(Result);
  Inc(aCount);
  Result^.Size := aCount mod 1000;
  if aDepth > 0 then
  begin
    SetLength(Result^.Children, aFanOut);
    for var I := 0 to aFanOut - 1 do
      Result^.Children[I] := BuildTree(aDepth - 1, aFanOut, aCount);
  end;
end;

procedure FreeTree(aNode: PNode);
begin
  for var Child in aNode^.Children do
    FreeTree(Child);
  Dispose(aNode);
end;

function SequentialTreeSize(aNode: PNode): Int64;
begin
  Result := aNode^.Size;
  for var Child in aNode^.Children do
    Inc(Result, SequentialTreeSize(Child));
end;

function TreeSize(aNode: PNode; aDepth: Integer): Int64;
begin
  // Deep in the tree the subtrees are small: no tasks there
  if aDepth >= 3 then
    Exit(SequentialTreeSize(aNode));
  var Sizes: array of Int64;
  SetLength(Sizes, Length(aNode^.Children));
  using var Group := TTaskGroup.Create do
  begin
    for var I := 0 to High(aNode^.Children) do
      Group.Spawn(I, Idx => Sizes[Idx] := TreeSize(aNode^.Children[Idx], aDepth + 1));
    Group.Wait;
  end;
  Result := aNode^.Size;
  for var S in Sizes do
    Inc(Result, S);
end;

procedure RecipeTree;
var
  Count: Int64 = 0;
begin
  var Root := BuildTree(7, 6, Count);
  Check(TreeSize(Root, 0) = SequentialTreeSize(Root), $'4. tree of {Count} nodes');
  FreeTree(Root);
end;

{ 5. Independent jobs of different size: one task per job }

function CountWords(const aText: string): Integer;
begin
  Result := 0;
  var InWord := False;
  for var Ch in aText do
    if Ch in [' ', #10, #13, #9] then
      InWord := False
    else if not InWord then
    begin
      InWord := True;
      Inc(Result);
    end;
end;

procedure RecipeDocuments;
var
  Docs: array of string;
  Counts: array of Integer;
begin
  SetLength(Docs, 2000);
  for var I := 0 to High(Docs) do
    Docs[I] := DupeString('lorem ipsum dolor ', 1 + (I * 37) mod 500);
  SetLength(Counts, Length(Docs));
  // Documents differ in size: idle threads steal the remaining ones
  using var Group := TTaskGroup.Create do
  begin
    for var I := 0 to High(Docs) do
      Group.Spawn(I, Idx => Counts[Idx] := CountWords(Docs[Idx]));
    Group.Wait;
  end;
  var Ok := True;
  for var I := 0 to High(Docs) do
    if Counts[I] <> CountWords(Docs[I]) then
      Ok := False;
  Check(Ok, '5. word count per document');
end;

{ 6. Search with an early stop }

function IsPrime(N: Int64): Boolean;
begin
  if N < 2 then
    Exit(False);
  var D: Int64 := 2;
  while D * D <= N do
  begin
    if N mod D = 0 then
      Exit(False);
    Inc(D);
  end;
  Result := True;
end;

// 6a. The smallest index whose value is prime, or -1. Chunks after a match
// already found stop at once. Group.Cancel would be wrong here: it also
// skips chunks before the match that have not started yet.
function FindFirstPrime(const aValues: array of Int64): Int64;
const
  CHUNK = 1000;
var
  Values: array of Int64;
  Best: Int64;
begin
  Values := Copy(aValues);
  Best := High(Int64);
  using var Group := TTaskGroup.Create do
  begin
    var Chunks := (Length(Values) + CHUNK - 1) div CHUNK;
    for var C := 0 to Chunks - 1 do
      Group.Spawn(C, Chunk =>
        begin
          var Last := Min(High(Values), (Chunk + 1) * CHUNK - 1);
          for var I := Chunk * CHUNK to Last do
          begin
            // A chunk after a match already found has nothing to add
            if I > Best then
              Exit;
            if IsPrime(Values[I]) then
            begin
              var Old: Int64;
              repeat
                Old := Best;
              until (I >= Old) or (InterlockedCompareExchange64(Best, I, Old) = Old);
              Exit;
            end;
          end;
        end);
    Group.Wait;
  end;
  if Best = High(Int64) then
    Result := -1
  else
    Result := Best;
end;

// 6b. Is there any prime at all: the first match cancels the chunks that
// have not started
function HasPrime(const aValues: array of Int64): Boolean;
const
  CHUNK = 1000;
var
  Values: array of Int64;
  Found: LongBool = False;
begin
  Values := Copy(aValues);
  using var Group := TTaskGroup.Create do
  begin
    for var C := 0 to (Length(Values) + CHUNK - 1) div CHUNK - 1 do
      Group.Spawn(C, Chunk =>
        begin
          for var I := Chunk * CHUNK to Min(High(Values), (Chunk + 1) * CHUNK - 1) do
            if IsPrime(Values[I]) then
            begin
              Found := True;
              Group.Cancel;
              Exit;
            end;
        end);
    Group.Wait;
  end;
  Result := Found;
end;

procedure RecipeSearch;
var
  Values: array of Int64;
begin
  SetLength(Values, 2000000);
  for var I := 0 to High(Values) do
    Values[I] := 1000000007 * 4;          // even: not prime
  Values[1234567] := 1000000007;           // prime
  Values[1500000] := 998244353;            // prime, later
  Check(FindFirstPrime(Values) = 1234567, '6a. first match');
  Check(HasPrime(Values), '6b. any match with cancellation');
  Values[1234567] := 4;
  Values[1500000] := 4;
  Check(not HasPrime(Values), '6b. no match');
end;

{ 7. Validation: the first exception of a task reaches Wait }

type
  EInvalidRecord = class(Exception);

procedure ValidateAll(const aAges: array of Integer);
var
  Ages: array of Integer;
begin
  Ages := Copy(aAges);
  TForkJoin.Each(0, High(Ages), I =>
    begin
      if (Ages[I] < 0) or (Ages[I] > 150) then
        raise EInvalidRecord.Create($'record {I}: age {Ages[I]}');
    end);
end;

procedure RecipeValidation;
var
  Ages: array of Integer;
  Message: string = '';
begin
  SetLength(Ages, 100000);
  for var I := 0 to High(Ages) do
    Ages[I] := I mod 100;
  Ages[77777] := -5;
  try
    ValidateAll(Ages);
  except
    on E: EInvalidRecord do
      Message := E.Message;
  end;
  Check(Message = 'record 77777: age -5', '7. validation error reaches the caller');
end;

{ 8. Monte Carlo: one random generator per chunk (Random is shared) }

function EstimatePi(aSamples: Int64): Double;
const
  CHUNKS = 128;
var
  Inside: Int64 = 0;
begin
  TForkJoin.Each(0, CHUNKS - 1, C =>
    begin
      var State: UInt64 := UInt64(C) * 2654435761 + 1;   // xorshift64, own state
      var Hits: Int64 := 0;
      for var I := 1 to aSamples div CHUNKS do
      begin
        State := State xor (State shl 13);
        State := State xor (State shr 7);
        State := State xor (State shl 17);
        var X := (State and $FFFFFFFF) / 4294967296.0;
        var Y := (State shr 32) / 4294967296.0;
        if X * X + Y * Y <= 1.0 then
          Inc(Hits);
      end;
      InterlockedExchangeAdd64(Inside, Hits);
    end, 1);
  Result := 4.0 * Inside / (aSamples div CHUNKS * CHUNKS);
end;

procedure RecipeMonteCarlo;
begin
  var Pi1 := EstimatePi(50000000);
  Check(Abs(Pi1 - Pi) < 0.001, $'8. Monte Carlo pi = {Pi1:0:5}');
end;

begin
  WriteLn($'ForkJoin recipes, {TForkJoin.WorkerCount} workers');
  RecipeImage;
  RecipeHistogram;
  RecipeQuickSort;
  RecipeTree;
  RecipeDocuments;
  RecipeSearch;
  RecipeValidation;
  RecipeMonteCarlo;
end.
