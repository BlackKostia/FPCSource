{
    This file is part of the Free Pascal run time library.
    Copyright (c) 2026 by the Free Pascal development team

    Memory spans: views of a contiguous range of elements of a static
    array, a dynamic array, a string or TBytes, without copying and without
    heap allocations.

      TReadOnlySpan<T> - read-only view
      TSpan<T>         - read/write view

    Index and range checks are always performed (the settings of the unit
    that specializes a generic do not apply to the generic's code, so they
    can't follow -Cr); unchecked access is available with for..in and Data.

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

 **********************************************************************}
{$IFNDEF FPC_DOTTEDUNITS}
unit spans;
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
  { TReadOnlySpan<T>

    A read-only view of Length elements starting at Data. A span does not
    own the elements and does not keep them alive: it must not outlive the
    array or string it was created from, and becomes invalid when that is
    resized (SetLength) or, for strings, modified. }

  generic TReadOnlySpan<T> = record
  public type
    PT = ^T;
    TElementArray = array of T;

    TEnumerator = record
    private
      { FNext..FEnd-1 are left; no pointer before Data or past the end is
        formed, so an empty span with Data = nil works as well }
      FCur, FNext, FEnd: PT;
      function GetCurrent: T; inline;
    public
      function MoveNext: Boolean; inline;
      property Current: T read GetCurrent;
    end;
  private
    FData: PT;
    FLength: SizeInt;
    function GetItem(AIndex: SizeInt): T; inline;
  public
    { A span of ALength elements at AData. Not checked: AData must point to
      at least ALength valid elements. }
    class function Create(AData: PT; ALength: SizeInt): TReadOnlySpan; static; overload;
    { The whole array (static or dynamic) or AStart..AStart+ACount-1 of it. }
    class function Create(const AArray: array of T): TReadOnlySpan; static; overload;
    class function Create(const AArray: array of T; AStart, ACount: SizeInt): TReadOnlySpan; static; overload;
    { Sub-spans; ERangeError if the range is not inside this span. }
    function Slice(AStart: SizeInt): TReadOnlySpan; overload;
    function Slice(AStart, ACount: SizeInt): TReadOnlySpan; overload;
    { Part AIndex (0..ACount-1) of ACount nearly equal, non-overlapping parts
      that together cover the span; for splitting work between threads. }
    function Chunk(AIndex, ACount: SizeInt): TReadOnlySpan;
    function ToArray: TElementArray;
    function IsEmpty: Boolean; inline;
    { True if the two spans share at least one element. }
    function Overlaps(const AOther: TReadOnlySpan): Boolean;
    function GetEnumerator: TEnumerator; inline;
    property Data: PT read FData;
    property Length: SizeInt read FLength;
    property Items[AIndex: SizeInt]: T read GetItem; default;
  end;

  { TSpan<T>

    A read/write view; otherwise the same as TReadOnlySpan<T>, to which it
    converts implicitly. Spans that don't overlap (e.g. different Chunks of
    one span) can be used from different threads at the same time. }

  generic TSpan<T> = record
  public type
    PT = ^T;
    TReadOnly = specialize TReadOnlySpan<T>;
    TElementArray = array of T;
    TEnumerator = TReadOnly.TEnumerator;
  private
    FData: PT;
    FLength: SizeInt;
    function GetItem(AIndex: SizeInt): T; inline;
    procedure SetItem(AIndex: SizeInt; const AValue: T); inline;
  public
    class function Create(AData: PT; ALength: SizeInt): TSpan; static; overload;
    class function Create(var AArray: array of T): TSpan; static; overload;
    class function Create(var AArray: array of T; AStart, ACount: SizeInt): TSpan; static; overload;
    class operator :=(const ASpan: TSpan): TReadOnly; inline;
    function AsReadOnly: TReadOnly; inline;
    function Slice(AStart: SizeInt): TSpan; overload;
    function Slice(AStart, ACount: SizeInt): TSpan; overload;
    function Chunk(AIndex, ACount: SizeInt): TSpan;
    { Copies ASource to the start of this span (ERangeError if it does not
      fit); overlapping spans are handled. Elements are assigned, so managed
      types (strings, interfaces) keep correct reference counts. }
    procedure CopyFrom(const ASource: TReadOnly);
    procedure Fill(const AValue: T);
    function ToArray: TElementArray;
    function IsEmpty: Boolean; inline;
    function Overlaps(const AOther: TReadOnly): Boolean;
    function GetEnumerator: TEnumerator; inline;
    property Data: PT read FData;
    property Length: SizeInt read FLength;
    property Items[AIndex: SizeInt]: T read GetItem write SetItem; default;
  end;

  TAnsiCharSpan = specialize TSpan<AnsiChar>;
  TReadOnlyAnsiCharSpan = specialize TReadOnlySpan<AnsiChar>;
  TWideCharSpan = specialize TSpan<WideChar>;
  TReadOnlyWideCharSpan = specialize TReadOnlySpan<WideChar>;
  TByteSpan = specialize TSpan<Byte>;
  TReadOnlyByteSpan = specialize TReadOnlySpan<Byte>;

{ Spans of the characters of a string (without the terminating #0). The
  read-only span must not outlive S or a modification of it; the writable
  one makes S unique first (copy-on-write). }
function SpanOf(const S: RawByteString): TReadOnlyAnsiCharSpan; overload;
function SpanOf(const S: UnicodeString): TReadOnlyWideCharSpan; overload;
function MutableSpanOf(var S: AnsiString): TAnsiCharSpan; overload;
function MutableSpanOf(var S: UnicodeString): TWideCharSpan; overload;

{ Implementation helpers. They are in the interface only because the
  generic code above is specialized in other units; do not call directly. }
procedure SpanIndexError(AIndex, ALength: SizeInt);
procedure SpanRangeError(AStart, ACount, ALength: SizeInt);
procedure SpanChunkError(AIndex, ACount: SizeInt);
function SpanChunkStart(ALength, AIndex, ACount: SizeInt; out AChunkLength: SizeInt): SizeInt;
function SpanOverlaps(AData1: Pointer; ALength1: SizeInt; AData2: Pointer; ALength2: SizeInt; AElementSize: SizeInt): Boolean;
{ AStart..AStart+ACount-1 lies inside 0..ALength-1 (written so that it can't
  overflow) }
function SpanRangeValid(AStart, ACount, ALength: SizeInt): Boolean; inline;

implementation

resourcestring
  SSpanIndex = 'Span index %d out of range (length %d)';
  SSpanRange = 'Span range start %d, count %d out of range (length %d)';
  SSpanChunk = 'Span chunk %d of %d is invalid';

procedure SpanIndexError(AIndex, ALength: SizeInt);
begin
  raise ERangeError.CreateFmt(SSpanIndex, [AIndex, ALength]);
end;

procedure SpanRangeError(AStart, ACount, ALength: SizeInt);
begin
  raise ERangeError.CreateFmt(SSpanRange, [AStart, ACount, ALength]);
end;

procedure SpanChunkError(AIndex, ACount: SizeInt);
begin
  raise ERangeError.CreateFmt(SSpanChunk, [AIndex, ACount]);
end;

function SpanChunkStart(ALength, AIndex, ACount: SizeInt; out AChunkLength: SizeInt): SizeInt;
var
  Q, R: SizeInt;
begin
  if (ACount <= 0) or (AIndex < 0) or (AIndex >= ACount) then
    SpanChunkError(AIndex, ACount);
  { the first R parts get one element more; no overflow for any length }
  Q := ALength div ACount;
  R := ALength mod ACount;
  if AIndex < R then
  begin
    Result := AIndex * (Q + 1);
    AChunkLength := Q + 1;
  end
  else
  begin
    Result := R * (Q + 1) + (AIndex - R) * Q;
    AChunkLength := Q;
  end;
end;

function SpanOverlaps(AData1: Pointer; ALength1: SizeInt; AData2: Pointer; ALength2: SizeInt; AElementSize: SizeInt): Boolean;
begin
  Result := (ALength1 > 0) and (ALength2 > 0) and
    (PByte(AData1) < PByte(AData2) + ALength2 * AElementSize) and
    (PByte(AData2) < PByte(AData1) + ALength1 * AElementSize);
end;

function SpanRangeValid(AStart, ACount, ALength: SizeInt): Boolean;
begin
  Result := (AStart >= 0) and (ACount >= 0) and (AStart <= ALength) and
    (ACount <= ALength - AStart);
end;

{ String spans }

function SpanOf(const S: RawByteString): TReadOnlyAnsiCharSpan;
begin
  Result := TReadOnlyAnsiCharSpan.Create(PAnsiChar(Pointer(S)), System.Length(S));
end;

function SpanOf(const S: UnicodeString): TReadOnlyWideCharSpan;
begin
  Result := TReadOnlyWideCharSpan.Create(PWideChar(Pointer(S)), System.Length(S));
end;

function MutableSpanOf(var S: AnsiString): TAnsiCharSpan;
begin
  UniqueString(S);
  Result := TAnsiCharSpan.Create(PAnsiChar(Pointer(S)), System.Length(S));
end;

function MutableSpanOf(var S: UnicodeString): TWideCharSpan;
begin
  UniqueString(S);
  Result := TWideCharSpan.Create(PWideChar(Pointer(S)), System.Length(S));
end;

{ TReadOnlySpan.TEnumerator }

function TReadOnlySpan.TEnumerator.GetCurrent: T;
begin
  Result := FCur^;
end;

function TReadOnlySpan.TEnumerator.MoveNext: Boolean;
begin
  Result := FNext <> FEnd;
  if Result then
  begin
    FCur := FNext;
    Inc(FNext);
  end;
end;

{ TReadOnlySpan }

class function TReadOnlySpan.Create(AData: PT; ALength: SizeInt): TReadOnlySpan;
begin
  if ALength < 0 then
    SpanRangeError(0, ALength, 0);
  Result.FData := AData;
  Result.FLength := ALength;
end;

class function TReadOnlySpan.Create(const AArray: array of T): TReadOnlySpan;
begin
  Result.FLength := System.Length(AArray);
  if Result.FLength > 0 then
    Result.FData := @AArray[0]
  else
    Result.FData := nil;
end;

class function TReadOnlySpan.Create(const AArray: array of T; AStart, ACount: SizeInt): TReadOnlySpan;
begin
  if not SpanRangeValid(AStart, ACount, System.Length(AArray)) then
    SpanRangeError(AStart, ACount, System.Length(AArray));
  Result.FLength := ACount;
  if ACount > 0 then
    Result.FData := @AArray[AStart]
  else
    Result.FData := nil;
end;

function TReadOnlySpan.GetItem(AIndex: SizeInt): T;
begin
  if PtrUInt(AIndex) >= PtrUInt(FLength) then
    SpanIndexError(AIndex, FLength);
  Result := FData[AIndex];
end;

function TReadOnlySpan.Slice(AStart: SizeInt): TReadOnlySpan;
begin
  Result := Slice(AStart, FLength - AStart);
end;

function TReadOnlySpan.Slice(AStart, ACount: SizeInt): TReadOnlySpan;
begin
  if not SpanRangeValid(AStart, ACount, FLength) then
    SpanRangeError(AStart, ACount, FLength);
  Result.FData := FData + AStart;
  Result.FLength := ACount;
end;

function TReadOnlySpan.Chunk(AIndex, ACount: SizeInt): TReadOnlySpan;
var
  Start, Len: SizeInt;
begin
  Start := SpanChunkStart(FLength, AIndex, ACount, Len);
  Result.FData := FData + Start;
  Result.FLength := Len;
end;

function TReadOnlySpan.ToArray: TElementArray;
var
  I: SizeInt;
begin
  Result := nil;
  SetLength(Result, FLength);
  for I := 0 to FLength - 1 do
    Result[I] := FData[I];
end;

function TReadOnlySpan.IsEmpty: Boolean;
begin
  Result := FLength = 0;
end;

function TReadOnlySpan.Overlaps(const AOther: TReadOnlySpan): Boolean;
begin
  Result := SpanOverlaps(FData, FLength, AOther.FData, AOther.FLength, SizeOf(T));
end;

function TReadOnlySpan.GetEnumerator: TEnumerator;
begin
  Result.FCur := nil;
  Result.FNext := FData;
  Result.FEnd := FData + FLength;
end;

{ TSpan }

class function TSpan.Create(AData: PT; ALength: SizeInt): TSpan;
begin
  if ALength < 0 then
    SpanRangeError(0, ALength, 0);
  Result.FData := AData;
  Result.FLength := ALength;
end;

class function TSpan.Create(var AArray: array of T): TSpan;
begin
  Result.FLength := System.Length(AArray);
  if Result.FLength > 0 then
    Result.FData := @AArray[0]
  else
    Result.FData := nil;
end;

class function TSpan.Create(var AArray: array of T; AStart, ACount: SizeInt): TSpan;
begin
  if not SpanRangeValid(AStart, ACount, System.Length(AArray)) then
    SpanRangeError(AStart, ACount, System.Length(AArray));
  Result.FLength := ACount;
  if ACount > 0 then
    Result.FData := @AArray[AStart]
  else
    Result.FData := nil;
end;

class operator TSpan.:=(const ASpan: TSpan): TReadOnly;
begin
  Result := TReadOnly.Create(ASpan.FData, ASpan.FLength);
end;

function TSpan.AsReadOnly: TReadOnly;
begin
  Result := TReadOnly.Create(FData, FLength);
end;

function TSpan.GetItem(AIndex: SizeInt): T;
begin
  if PtrUInt(AIndex) >= PtrUInt(FLength) then
    SpanIndexError(AIndex, FLength);
  Result := FData[AIndex];
end;

procedure TSpan.SetItem(AIndex: SizeInt; const AValue: T);
begin
  if PtrUInt(AIndex) >= PtrUInt(FLength) then
    SpanIndexError(AIndex, FLength);
  FData[AIndex] := AValue;
end;

function TSpan.Slice(AStart: SizeInt): TSpan;
begin
  Result := Slice(AStart, FLength - AStart);
end;

function TSpan.Slice(AStart, ACount: SizeInt): TSpan;
begin
  if not SpanRangeValid(AStart, ACount, FLength) then
    SpanRangeError(AStart, ACount, FLength);
  Result.FData := FData + AStart;
  Result.FLength := ACount;
end;

function TSpan.Chunk(AIndex, ACount: SizeInt): TSpan;
var
  Start, Len: SizeInt;
begin
  Start := SpanChunkStart(FLength, AIndex, ACount, Len);
  Result.FData := FData + Start;
  Result.FLength := Len;
end;

procedure TSpan.CopyFrom(const ASource: TReadOnly);
var
  I, N: SizeInt;
  Src: PT;
begin
  N := ASource.Length;
  if N > FLength then
    SpanRangeError(0, N, FLength);
  Src := ASource.Data;
  if (N = 0) or (Src = FData) then
    Exit;
  { assign element by element (reference counts of managed types); copy
    backwards when the destination starts inside the source }
  if (FData > Src) and (FData < Src + N) then
    for I := N - 1 downto 0 do
      FData[I] := Src[I]
  else
    for I := 0 to N - 1 do
      FData[I] := Src[I];
end;

procedure TSpan.Fill(const AValue: T);
var
  I: SizeInt;
begin
  for I := 0 to FLength - 1 do
    FData[I] := AValue;
end;

function TSpan.ToArray: TElementArray;
var
  I: SizeInt;
begin
  Result := nil;
  SetLength(Result, FLength);
  for I := 0 to FLength - 1 do
    Result[I] := FData[I];
end;

function TSpan.IsEmpty: Boolean;
begin
  Result := FLength = 0;
end;

function TSpan.Overlaps(const AOther: TReadOnly): Boolean;
begin
  Result := SpanOverlaps(FData, FLength, AOther.Data, AOther.Length, SizeOf(T));
end;

function TSpan.GetEnumerator: TEnumerator;
begin
  Result := AsReadOnly.GetEnumerator;
end;

end.
