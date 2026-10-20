{ %OPT=-gh }
{ {$modeswitch using}: the resource of "using ... do" is freed at the end of
  the statement, also after an exception, Exit, Break and Continue; several
  resources are freed in reverse order }
{$mode objfpc}{$H+}
{$modeswitch using}
program tusing1;

uses
  SysUtils;

type
  TRes = class
  public
    Name: string;
    constructor Create(const AName: string);
    destructor Destroy; override;
  end;

  EBoom = class(Exception);

  TFailing = class(TRes)
  public
    constructor Create(const AName: string);
  end;

var
  Log: string;
  Alive: Integer;

constructor TRes.Create(const AName: string);
begin
  Name := AName;
  Inc(Alive);
  Log := Log + '+' + Name;
end;

destructor TRes.Destroy;
begin
  Dec(Alive);
  Log := Log + '-' + Name;
  inherited Destroy;
end;

constructor TFailing.Create(const AName: string);
begin
  inherited Create(AName);
  raise EBoom.Create('constructor of ' + AName);
end;

procedure Check(Cond: Boolean; Code: Integer);
begin
  if not Cond then
    begin
      WriteLn('failed ', Code, ' log=', Log, ' alive=', Alive);
      Halt(Code);
    end;
end;

procedure Expect(const Expected: string; Code: Integer);
begin
  Check(Log = Expected, Code);
  Check(Alive = 0, Code + 100);
  Log := '';
end;

{ the resource is freed after the statement }
procedure Simple;
begin
  using var R := TRes.Create('a') do
    begin
      Check(R.Name = 'a', 1);
      Log := Log + '.';
    end;
  Log := Log + '|';
  Expect('+a.-a|', 2);
end;

{ the type can be given explicitly, also a base class }
procedure ExplicitType;
begin
  using var R: TObject := TRes.Create('b') do
    Check(R is TRes, 3);
  Expect('+b-b', 4);
end;

{ an exception in the statement frees the resource and propagates }
procedure ExceptionInBody;
var
  Caught: Boolean;
begin
  Caught := False;
  try
    using var R := TRes.Create('c') do
      raise EBoom.Create('body');
  except
    on E: EBoom do
      Caught := E.Message = 'body';
  end;
  Check(Caught, 5);
  Expect('+c-c', 6);
end;

procedure WithExit;
begin
  using var R := TRes.Create('d') do
    begin
      Log := Log + '.';
      Exit;
    end;
  Log := Log + 'unreachable';
end;

procedure LoopBreakContinue;
var
  I: Integer;
begin
  for I := 1 to 5 do
    using var R := TRes.Create(IntToStr(I)) do
      begin
        if I = 2 then
          Continue;
        if I = 4 then
          Break;
        Log := Log + '.';
      end;
  Expect('+1.-1+2-2+3.-3+4-4', 9);
  I := 0;
  while I < 2 do
    begin
      Inc(I);
      using var R := TRes.Create('w' + IntToStr(I)) do
        Log := Log + '.';
    end;
  Expect('+w1.-w1+w2.-w2', 10);
end;

{ several resources are freed in reverse order, a later resource can use an
  earlier one }
procedure Several;
begin
  using var A := TRes.Create('x'), var B := TRes.Create(A.Name + 'y') do
    Log := Log + '.';
  Expect('+x+xy.-xy-x', 11);
end;

{ when the constructor of a later resource fails, the earlier resources are
  freed; the failed object is destroyed by the constructor only }
procedure FailingConstructor;
var
  Caught: Boolean;
begin
  Caught := False;
  try
    using var A := TRes.Create('p'), var B := TFailing.Create('q') do
      Log := Log + 'unreachable';
  except
    on E: EBoom do
      Caught := E.Message = 'constructor of q';
  end;
  Check(Caught, 12);
  Expect('+p+q-q-p', 13);
end;

{ the resources are nil-safe }
procedure NilResource;
begin
  using var R: TRes := nil do
    Check(R = nil, 14);
  Expect('', 15);
end;

{ nested using statements and the same name in sibling statements }
procedure Nested;
begin
  using var R := TRes.Create('o') do
    using var S := TRes.Create('i') do
      Log := Log + '.';
  Expect('+o+i.-i-o', 16);
  using var R := TRes.Create('r1') do
    Log := Log + '.';
  using var R := TObject.Create do
    Check(R.ClassType = TObject, 17);
  Expect('+r1.-r1', 18);
end;

{ the resource variable is visible in the statement only }
var
  R: Integer;

procedure Shadow;
begin
  R := 7;
  using var R := TRes.Create('s') do
    Check(R.Name = 's', 19);
  Check(R = 7, 20);
  Expect('+s-s', 21);
end;

{ in a nested routine, which uses the resource of the outer one }
procedure Outer;
  procedure Inner;
  begin
    using var R := TRes.Create('n') do
      Log := Log + '.';
  end;
begin
  Inner;
  Expect('+n.-n', 22);
end;

{ FreeAndNil (constref) sets the resource to nil: it is not freed twice }
procedure FreedInBody;
begin
  using var R := TRes.Create('z') do
    begin
      FreeAndNil(R);
      Log := Log + '.';
    end;
  Expect('+z-z.', 26);
end;

{ in a function with a result }
function MakeName: string;
begin
  using var R := TRes.Create('f') do
    Result := R.Name + R.Name;
end;

begin
  Simple;
  ExplicitType;
  ExceptionInBody;
  WithExit;
  Expect('+d.-d', 7);
  LoopBreakContinue;
  Several;
  FailingConstructor;
  NilResource;
  Nested;
  Shadow;
  Outer;
  FreedInBody;
  Check(MakeName = 'ff', 23);
  Expect('+f-f', 24);
  { in the main program }
  using var M := TRes.Create('m') do
    Log := Log + '.';
  Expect('+m.-m', 25);
  WriteLn('ok');
end.
