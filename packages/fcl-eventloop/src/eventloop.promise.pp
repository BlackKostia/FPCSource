{
    This file is part of the Free Component Library (FCL)
    Copyright (c) 2026 by the Free Pascal development team

    Scalable Asynchronous I/O Event Loop - futures completed by I/O callbacks

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.
}
{$mode objfpc}{$H+}
{$modeswitch functionreferences}
{$modeswitch anonymousfunctions}

unit eventloop.promise;

interface

uses
  SysUtils, System.Threading;

type
  { A future that is completed from outside, typically from an event loop
    callback, instead of by running a computation.

    The future is created in the Created state and is only started when the
    promise is completed: no pool thread is occupied while the operation is
    pending. Once started, its body returns the stored value or raises the
    stored exception. Exactly one of the TrySet* methods succeeds. }
  generic TLoopPromise<T> = class(TInterfacedObject)
  public type
    TFutureT = specialize IFuture<T>;
  private
    FFuture: TFutureT;
    FState: Integer; { 0 = pending, 1 = completed }
    FValue: T;
    FError: Exception;
    function TakeResult: T;
    function Claim: TFutureT;
  public
    constructor Create;
    destructor Destroy; override;
    function TrySetResult(const AValue: T): Boolean;
    { Takes ownership of AError, also when it returns False. }
    function TrySetException(AError: Exception): Boolean;
    function TrySetCanceled: Boolean;
    function IsPending: Boolean;
    property Future: TFutureT read FFuture;
  end;

implementation

{ TLoopPromise }

constructor TLoopPromise.Create;
var
  LSelf: TLoopPromise;
  LKeep: IInterface;
begin
  inherited Create;
  LSelf := Self;
  { The future's body keeps the promise alive until it has run. The
    promise drops its reference to the future when it is completed,
    which breaks the cycle. }
  LKeep := Self;
  FFuture := specialize TFuture<T>.Create(nil, nil,
    function: T
    begin
      if LKeep = nil then;
      Result := LSelf.TakeResult;
    end,
    TThreadPool.Default);
end;

destructor TLoopPromise.Destroy;
begin
  FreeAndNil(FError);
  inherited Destroy;
end;

function TLoopPromise.TakeResult: T;
var
  LError: Exception;
begin
  LError := FError;
  if LError <> nil then
  begin
    FError := nil;
    raise LError;
  end;
  Result := FValue;
end;

function TLoopPromise.Claim: TFutureT;
begin
  Result := nil;
  if InterlockedCompareExchange(FState, 1, 0) <> 0 then
    Exit;
  Result := FFuture;
end;

function TLoopPromise.TrySetResult(const AValue: T): Boolean;
var
  LFuture: TFutureT;
begin
  LFuture := Claim;
  Result := LFuture <> nil;
  if not Result then
    Exit;
  FValue := AValue;
  FFuture := nil;
  LFuture.Start;
end;

function TLoopPromise.TrySetException(AError: Exception): Boolean;
var
  LFuture: TFutureT;
begin
  LFuture := Claim;
  Result := LFuture <> nil;
  if not Result then
  begin
    AError.Free;
    Exit;
  end;
  FError := AError;
  FFuture := nil;
  LFuture.Start;
end;

function TLoopPromise.TrySetCanceled: Boolean;
var
  LFuture: TFutureT;
begin
  LFuture := Claim;
  Result := LFuture <> nil;
  if not Result then
    Exit;
  FFuture := nil;
  { A task that has not been started completes as Canceled at once. }
  LFuture.Cancel;
end;

function TLoopPromise.IsPending: Boolean;
begin
  Result := InterlockedCompareExchange(FState, 0, 0) = 0;
end;

end.
