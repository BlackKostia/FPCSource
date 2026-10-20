{$mode objfpc}
uses
  SysUtils,Contnrs;

var
  errors : Integer;

// Test for Hashing
procedure Test;
 var HL:TFPHashList;
     i,n,steps:integer;
     dat:array[0..5]of pinteger;

begin
 HL:=TFpHashList.Create;
 HL.Capacity:=389;

 // Create pointer for data
 for i:=0 to 5 do
  begin
   dat[i]:=new(pinteger);
   dat[i]^:=i;
  end;

 // add A..F with pointer
 for i:=0 to 5 do
    Writeln('HL.Add: '+chr(i+65)+' = Index: '
                    +IntToStr(HL.Add(chr(i+65),dat[i])));

 { get collisions: since TFPHashList uses MurmurHash3 (2025) two of these
   names may share a bucket, which is fine; every name must be found with
   its own data, and the collision chains must be finite and only lead to
   entries of the list }
 for i:=0 to 5 do
   begin
    Writeln('--------------');
    Writeln('Collision for Index: '+IntToStr(i));
    n:=HL.FindIndexOf(chr(i+65));
    if (n<0) or (HL.NameOfIndex(n)<>chr(i+65)) or (HL[n]<>dat[i]) then
      begin
        Writeln('wrong entry found for ',chr(i+65));
        inc(errors);
      end;
    steps:=0;
    while n>=0 do
     begin
      Writeln('Index: '+IntToStr(n)+
                      ' | NameOfIndex: '+HL.NameOfIndex(n)+
                      ' | HashOfIndex: '+IntToStr(HL.HashOfIndex(n))+
                      ' | NextCollision: '+IntToStr(HL.GetNextCollision(n)));
      n:=HL.GetNextCollision(n);
      inc(steps);
      if (n>=HL.Count) or (steps>HL.Count) then
        begin
          Writeln('invalid collision chain');
          inc(errors);
          break;
        end;
     end; //while
   end; //for

 HL.Free;
 for i:=0 to 5 do dispose(dat[i]);
end;

begin
  Test;
  if errors>0 then
    halt(1);
end.

