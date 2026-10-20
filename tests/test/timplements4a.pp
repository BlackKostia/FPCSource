{ %SKIPTARGET=go32v2 }
{ %OPT=-gh }
{ An interface implemented through a class-type property: assigning the
  object to an interface calls the getter and returns the interface of the
  delegate itself, with a reference of its own (as in Delphi). So the
  interface stays valid and queryable after the field is set to nil, the
  delegate lives as long as such references exist, and the outer object
  no longer provides the interface. }
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
  { the interface of the delegate }
  if pointer(i1)<>pointer(IInterface(o1.fi)) then
    halt(1);
  i1.QueryInterface(IInterface,i2);
  writeln('i2 queried the first time');
  if i2=nil then
    halt(2);
  i2:=nil;
  writeln('setting o1.fi to nil');
  o1.fi:=nil;
  { i1 still refers to the delegate, which it keeps alive }
  if i1.QueryInterface(IInterface,i2)<>S_OK then
    halt(3);
  writeln('i2 queried the second time');
  if i2=nil then
    halt(4);
  i2:=nil;
  { without a delegate the object does not provide the interface }
  if o1.GetInterface(IInterface,i2) or (i2<>nil) then
    halt(5);
  o1.free;
  { releasing the last reference frees the delegate (checked by -gh) }
  i1:=nil;
  writeln('ok');
end.
