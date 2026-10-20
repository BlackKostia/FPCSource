{ %OPT=-gh }
{ An interface implemented through a class-type property: assigning the
  object to an interface returns the interface of the delegate itself,
  with a reference of its own (as in Delphi). So the interface stays valid
  after the outer object is freed: the delegate lives as long as such
  references exist. }
{$ifdef fpc}
{$mode objfpc}
{$endif fpc}
uses
  classes;

type
  to1 = class(TObject,IInterface)
    fi : TInterfacedObject;
    property i : TInterfacedObject read fi implements IInterface;
  end;

var
  o1 : to1;
  i1,i2 : IInterface;
begin
  {$if declared(HaltOnNotReleased)}
  HaltOnNotReleased:=True;
  {$endif}
  o1:=to1.create;
  o1.fi:=TInterfacedObject.Create;
  writeln('o1 and o1.fi created');
  i1:=o1;
  i1.QueryInterface(IInterface,i2);
  writeln('i2 queried the first time');
  if i2=nil then
    halt(1);
  i2:=nil;
  writeln('freeing o1');
  o1.free;
  { i1 refers to the delegate, not to the freed object }
  if i1.QueryInterface(IInterface,i2)<>S_OK then
    halt(2);
  writeln('i2 queried after freeing o1');
  if i2=nil then
    halt(3);
  i2:=nil;
  { releasing the last reference frees the delegate (checked by -gh) }
  i1:=nil;
  writeln('ok');
end.
