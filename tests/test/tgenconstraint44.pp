{ class type and interface constraints in result types of
  generic functions declared in a unit interface }
program tgenconstraint44;

{$mode objfpc}{$H+}

uses
  ugenconstraint44;

type
  TDerived = class(TBase)
    function Name: String; override;
  end;

  TGreeter = class(TInterfacedObject, IGreeter)
    function Greet: String;
  end;

function TDerived.Name: String;
begin
  Result := 'derived';
end;

function TGreeter.Greet: String;
begin
  Result := 'hello';
end;

var
  d: TDerived;
  hb: specialize TClassHolder<TDerived>;
  hi: specialize TIntfHolder<IGreeter>;
begin
  d := TDerived.Create;
  hb := specialize HoldBase<TDerived>(d);
  if hb.Item.Name <> 'derived' then
    Halt(1);
  hi := specialize HoldIntf<IGreeter>(TGreeter.Create);
  if hi.Item.Greet <> 'hello' then
    Halt(2);
  d.Free;
  Writeln('ok');
end.
