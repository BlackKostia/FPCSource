unit ugenconstraint45;

{$mode objfpc}{$H+}

interface

type
  generic TPair<K: class; V> = record
    Key: K;
    Value: V;
  end;

{ several type parameters, only some of them constrained, in one group and
  in separate groups }
generic function MakePair<K: class; V>(aKey: K; const aValue: V): specialize TPair<K, V>;
generic function SwapPair<V; K: class>(const aValue: V; aKey: K): specialize TPair<K, V>;

{ overloads of a constrained generic function }
generic function Count<T: class>(const aPair: specialize TPair<T, LongInt>): LongInt; overload;
generic function Count<T: class>(const aPair: specialize TPair<T, String>): LongInt; overload;

implementation

generic function MakePair<K; V>(aKey: K; const aValue: V): specialize TPair<K, V>;
begin
  Result.Key := aKey;
  Result.Value := aValue;
end;

generic function SwapPair<V; K>(const aValue: V; aKey: K): specialize TPair<K, V>;
begin
  Result.Key := aKey;
  Result.Value := aValue;
end;

generic function Count<T>(const aPair: specialize TPair<T, LongInt>): LongInt;
begin
  Result := aPair.Value;
end;

generic function Count<T>(const aPair: specialize TPair<T, String>): LongInt;
begin
  Result := Length(aPair.Value);
end;

end.
