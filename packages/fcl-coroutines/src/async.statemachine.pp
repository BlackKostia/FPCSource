{
    This file is part of the Free Component Library (FCL)
    Copyright (c) 2026 by the Free Pascal development team

    Async State Machine Builders & TaskCompletionSource (Phase 4, Step 1 & 2)
    Provides runtime foundation for stackless async/await state machines

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.
}
{$mode objfpc}{$H+}
{$modeswitch advancedrecords}
{$modeswitch functionreferences}
{$modeswitch anonymousfunctions}

unit async.statemachine;

interface

uses
  SysUtils, Classes, SyncObjs,
  System.Threading,
  async.types;

type
  { TTaskCompletionSource<T> now lives in System.Threading, which the
    compiler's state-machine async routines need on every platform. }

  { State machine method builder for typed futures }
  generic TAsyncTaskMethodBuilder<TResult> = record
  private type
    TSource = specialize TTaskCompletionSource<TResult>;
  private
    FSource: TSource;
    FTask: specialize IFuture<TResult>;
    procedure EnsureSource;
  public
    class function Create: specialize TAsyncTaskMethodBuilder<TResult>; static;
    function GetTask: specialize IFuture<TResult>;
    procedure Start(const AStateMachine: IAsyncStateMachine);
    procedure AwaitOnCompleted(const ATask: ITask; const AStateMachine: IAsyncStateMachine);
    { SetResult and SetException complete the task and free the source. }
    procedure SetResult(const AResult: TResult);
    procedure SetException(const AException: Exception);
    property Task: specialize IFuture<TResult> read GetTask;
  end;

  { State machine method builder for void ITask }
  TAsyncTaskBuilder = record
  private
    FSource: specialize TTaskCompletionSource<Boolean>;
    FTask: ITask;
    procedure EnsureSource;
  public
    class function Create: TAsyncTaskBuilder; static;
    function GetTask: ITask;
    procedure Start(const AStateMachine: IAsyncStateMachine);
    procedure AwaitOnCompleted(const ATask: ITask; const AStateMachine: IAsyncStateMachine);
    procedure SetResult;
    procedure SetException(const AException: Exception);
    property Task: ITask read GetTask;
  end;

implementation

{ TAsyncTaskMethodBuilder<TResult> }

class function TAsyncTaskMethodBuilder.Create: specialize TAsyncTaskMethodBuilder<TResult>;
begin
  Result := Default(specialize TAsyncTaskMethodBuilder<TResult>);
  Result.EnsureSource;
end;

procedure TAsyncTaskMethodBuilder.EnsureSource;
begin
  if (FSource = nil) and (FTask = nil) then
  begin
    FSource := TSource.Create;
    FTask := FSource.Task;
  end;
end;

function TAsyncTaskMethodBuilder.GetTask: specialize IFuture<TResult>;
begin
  EnsureSource;
  Result := FTask;
end;

procedure TAsyncTaskMethodBuilder.Start(const AStateMachine: IAsyncStateMachine);
begin
  EnsureSource;
  AStateMachine.MoveNext;
end;

procedure TAsyncTaskMethodBuilder.AwaitOnCompleted(const ATask: ITask; const AStateMachine: IAsyncStateMachine);
var
  LState: IAsyncStateMachine;
begin
  LState := AStateMachine;
  ATask.ContinueWith(
    procedure(ACompletedTask: ITask)
    begin
      LState.MoveNext;
    end);
end;

procedure TAsyncTaskMethodBuilder.SetResult(const AResult: TResult);
begin
  EnsureSource;
  if FSource <> nil then
  begin
    FSource.SetResult(AResult);
    FreeAndNil(FSource);
  end;
end;

procedure TAsyncTaskMethodBuilder.SetException(const AException: Exception);
begin
  EnsureSource;
  if FSource <> nil then
  begin
    FSource.SetException(AException);
    FreeAndNil(FSource);
  end
  else
    AException.Free;
end;

{ TAsyncTaskBuilder }

class function TAsyncTaskBuilder.Create: TAsyncTaskBuilder;
begin
  Result := Default(TAsyncTaskBuilder);
  Result.EnsureSource;
end;

procedure TAsyncTaskBuilder.EnsureSource;
begin
  if (FSource = nil) and (FTask = nil) then
  begin
    FSource := specialize TTaskCompletionSource<Boolean>.Create;
    FTask := FSource.Task;
  end;
end;

function TAsyncTaskBuilder.GetTask: ITask;
begin
  EnsureSource;
  Result := FTask;
end;

procedure TAsyncTaskBuilder.Start(const AStateMachine: IAsyncStateMachine);
begin
  EnsureSource;
  AStateMachine.MoveNext;
end;

procedure TAsyncTaskBuilder.AwaitOnCompleted(const ATask: ITask; const AStateMachine: IAsyncStateMachine);
var
  LState: IAsyncStateMachine;
begin
  LState := AStateMachine;
  ATask.ContinueWith(
    procedure(ACompletedTask: ITask)
    begin
      LState.MoveNext;
    end);
end;

procedure TAsyncTaskBuilder.SetResult;
begin
  EnsureSource;
  if FSource <> nil then
  begin
    FSource.SetResult(True);
    FreeAndNil(FSource);
  end;
end;

procedure TAsyncTaskBuilder.SetException(const AException: Exception);
begin
  EnsureSource;
  if FSource <> nil then
  begin
    FSource.SetException(AException);
    FreeAndNil(FSource);
  end
  else
    AException.Free;
end;

end.
