{ a unit compiled for ThreadSanitizer }
unit utsan4;

{$mode objfpc}

interface

var
  Shared: LongInt;

procedure Touch;

implementation

procedure Touch;
begin
  Inc(Shared);
end;

end.
