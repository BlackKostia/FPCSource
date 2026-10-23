{
    This file is part of the Free Component Library (FCL)
    Copyright (c) 2026 by the Free Pascal development team

    fcl-async: Coroutines, Fibers, and Async State Machines (Phase 4)
    Public umbrella unit

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.
}
{$mode objfpc}{$H+}
{$modeswitch functionreferences}
{$modeswitch anonymousfunctions}

unit fclasync;

interface

uses
  SysUtils,
  System.Threading,
  eventloop.types,
  eventloop.core,
  async.types,
  async.fiber,
  async.generator,
  async.statemachine;

type
  { Re-export non-generic types }
  TFiberState = async.types.TFiberState;
  EFiberException = async.types.EFiberException;
  EAsyncException = async.types.EAsyncException;
  IAsyncStateMachine = async.types.IAsyncStateMachine;
  TProc = async.types.TProc;

  TFiber = async.fiber.TFiber;
  TAsyncTaskBuilder = async.statemachine.TAsyncTaskBuilder;

{ Ergonomic modern async helper functions }

{ Run asynchronous function returning IFuture<T> without blocking caller thread }
generic function RunAsync<T>(const AFunc: specialize TFunc<T>; ALoop: IEventLoop = nil; AStackSize: Cardinal = 128 * 1024): specialize IFuture<T>;

{ Run asynchronous procedure returning ITask without blocking caller thread }
function SpawnAsync(const AProc: TProc; ALoop: IEventLoop = nil; AStackSize: Cardinal = 128 * 1024): ITask;

{ Compiler lowering helpers for lower_async_fiber phase }
generic function AsyncFiberRun<T>(const AFunc: specialize TFunc<T>): specialize IFuture<T>;
function AsyncFiberRunTask(const AProc: TProc): ITask;

{ Non-blocking sleep: yields fiber to event loop / pool until timer expiry }
procedure AsyncSleep(AMilliseconds: Cardinal; ALoop: IEventLoop = nil);

implementation

generic function RunAsync<T>(const AFunc: specialize TFunc<T>; ALoop: IEventLoop; AStackSize: Cardinal): specialize IFuture<T>;
begin
  Result := TFiber.specialize Async<T>(AFunc, ALoop, AStackSize);
end;

function SpawnAsync(const AProc: TProc; ALoop: IEventLoop; AStackSize: Cardinal): ITask;
begin
  Result := TFiber.Spawn(AProc, ALoop, AStackSize);
end;

generic function AsyncFiberRun<T>(const AFunc: specialize TFunc<T>): specialize IFuture<T>;
begin
  Result := async.fiber.specialize AsyncFiberRun<T>(AFunc);
end;

function AsyncFiberRunTask(const AProc: TProc): ITask;
begin
  Result := async.fiber.AsyncFiberRunTask(AProc);
end;

procedure AsyncSleep(AMilliseconds: Cardinal; ALoop: IEventLoop);
begin
  TFiber.Sleep(AMilliseconds, ALoop);
end;

end.
