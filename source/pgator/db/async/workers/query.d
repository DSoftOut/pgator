// Written in D programming language
/**
*    Part of asynchronous pool realization.
*    
*    Copyright: © 2014 DSoftOut
*    License: Subject to the terms of the MIT license, as written in the included LICENSE file.
*    Authors: NCrashed <ncrashed@gmail.com>
*/
module pgator.db.async.workers.query;

import dlogg.log;
import pgator.db.connection;
import pgator.db.async.transaction;
import pgator.db.async.respond;
import pgator.db.async.workers.handler;
import std.concurrency;
import std.container;
import std.range;
import std.array;
import core.thread;
import derelict.pq.pq;

static void queringChecker(shared ILogger logger)
{
    try
    {
        setMaxMailboxSize(thisTid, 0, OnCrowding.block);
        Thread.getThis.isDaemon = true;
       
        DList!Element list;
        auto ids = ThreadIds.receive();
      
        bool exit = false;
        Tid exitTid;
        size_t last = list[].walkLength;
        while(!exit || last > 0)
        {
            while(receiveTimeout(dur!"msecs"(1)
                , (Tid sender, bool v) 
                {
                    exit = v; 
                    exitTid = sender;
                }
                , (Tid sender, shared IConnection conn, shared Transaction transaction) 
                {
                    list.insert(new Element(sender, conn, cast(immutable)transaction, logger));
                }
                , (Tid sender, string com) 
                {
                    if(com == "length")
                    {
                        sender.send(thisTid, list[].walkLength);
                    }
                }
                , (Variant v) { assert(false, "Unhandled message!"); }
            )) {}
           
            DList!Element nextList;
            foreach(elem; list[])
            {
                final switch(elem.stage)
                {
                    case Element.Stage.MoreQueries:
                    {
                        elem.postQuery();
                        nextList.insert(elem);
                        break;             
                    }
                    case Element.Stage.Proccessing:
                    {
                        elem.stepQuery();
                        nextList.insert(elem);
                        break;            
                    }
                    case Element.Stage.Finished:
                    {
                        elem.sendRespond();
                        if(exit) elem.conn.disconnect();
                        else ids.freeCheckerId.send("add", elem.conn);
                    }
                }
            }
            list.clear();
            list = nextList;
            last = list[].walkLength;
        }

        exitTid.send(true);
        logger.logDebug("Quering thread exited!");
    } catch (Throwable th)
    {
        logger.logError("AsyncPool: quering thread died!");
        logger.logError(text(th));
    }
}

private class Element
{
    Tid sender;
    shared IConnection conn;
       
    immutable Transaction transaction;
    private
    {
        size_t transactPos = 0;
        size_t currQueryIndex = 0;
        size_t paramsPassed = 0;
        immutable string[] varsQueries;
        size_t localVars = 0;
        bool transStarted = false;
        bool transEnded = false;
        bool commandPosting = false;
        bool rollbackNeeded = false;
        bool rollbacked = false;
        shared(ILogger) logger;
    }
       
    enum Stage
    {
        MoreQueries,
        Proccessing,
        Finished
    }
    Stage stage = Stage.MoreQueries;
    private Respond respond;
       
    this(Tid sender, shared IConnection conn, immutable Transaction transaction, shared ILogger logger)
    {
        this.sender = sender;
        this.conn = conn;
        this.transaction = transaction;
        this.logger = logger;
        
        auto builder = appender!(string[]);   
        foreach(key, value; transaction.vars)
        {
            builder.put(`SET LOCAL "` ~ key ~ `" = '` ~ value ~ `';`);
        } 
        varsQueries = builder.data.idup;
    }
       
    private void wrapError(void delegate() func, bool startRollback = true)
    {
        try func();
        catch(QueryException e)
        {
            respond = Respond(e, conn);         
            if(startRollback)
            {       
                rollbackNeeded = true; 
                stage = Stage.MoreQueries;
            } else
            {
                stage = Stage.Finished;
            }
            return;
        }
        catch (Exception e)
        {
            respond = Respond(new QueryException("Internal error: "~e.msg), conn);
            if(startRollback)
            {       
                rollbackNeeded = true;
                stage = Stage.MoreQueries;
            } else
            {
                stage = Stage.Finished;
            }
            return;
        }
           
        stage = Stage.Proccessing;   
    }
        
    void postQuery()
    {
        assert(stage == Stage.MoreQueries); 

        try
        {
            if(rollbackNeeded)
            {
                wrapError((){ conn.postQuery("rollback;", []); }, false);
                rollbacked = true;
                return;
            }
               
            if(!transStarted)
            {
                transStarted = true; 
                wrapError((){ conn.postQuery("begin;", []); });            
                return;
            }
               
            if(localVars < varsQueries.length)
            {
                wrapError(()
                { 
                    conn.postQuery(varsQueries[localVars], []); 
                    localVars++;
                });              
                return;
            }
               
            if(transactPos < transaction.commands.length)
            {
                commandPosting = true;
                wrapError(()
                { 
                    assert(transactPos < transaction.commands.length);
                    auto query = transaction.commands[transactPos];
                           
                    assert(transactPos < transaction.argnums.length);
                    assert(transaction.argnums[transactPos] + paramsPassed <= transaction.params.length);
                    auto params = transaction.params[paramsPassed .. paramsPassed + transaction.argnums[transactPos]].dup;
                           
                    conn.postQuery(query, params);  
                    currQueryIndex = transactPos; 
                    
                    paramsPassed += transaction.argnums[transactPos];
                    transactPos++; 
                });             
                return;
            }
               
            if(!transEnded)
            {
                commandPosting = false;
                transEnded = true;
                wrapError((){ conn.postQuery("commit;", []); });           
                return;
            }
        }
        catch(Error err)
        {
            logger.logError(text("Internal unrecoverable error with transaction: ", err.msg));
            logger.logError(transaction.text);
            logger.logError(text("Stack trace: ", err));
            throw err;
        }
        assert(false);
    }
       
    private bool hasMoreQueries()
    {
        if(!rollbackNeeded)
        {
            return !transStarted || !transEnded || localVars < varsQueries.length || transactPos < transaction.commands.length;
        }
        return !rollbacked;
    }
       
    private bool needCollectResult()
    {
        return commandPosting;
    }
       
    void stepQuery()
    {
        assert(stage == Stage.Proccessing);                
        
        try
        {   
            final switch(conn.pollQueringStatus())
            {
                case QueringStatus.Pending:
                { 
                    return;                
                }
                case QueringStatus.Error:
                {
                    try conn.pollQueryException();
                    catch(QueryException e)
                    {
                        respond = Respond(e, conn);
                        rollbackNeeded = true;
                        return;
                    } 
                    catch (Exception e)
                    {
                        respond = Respond(new QueryException("Internal error: "~e.msg), conn);
                        rollbackNeeded = true;
                        return;
                    }
                    break;
                }
                case QueringStatus.Finished:
                {
                    try 
                    {
                        if(rollbackNeeded)
                        {
                            rollbacked = true;
                        }
                          
                        auto resList = conn.getQueryResult;
                        if(needCollectResult) 
                        {
                            if(!respond.collect(resList, conn, transaction.oneRowConstraints[currQueryIndex], currQueryIndex))
                            {
                                rollbackNeeded = true;  
                                commandPosting = false;
                                stage = Stage.MoreQueries;
                                return;
                            }
                        } else // setting vars can fail
                        {
                            bool failed = false;
                            foreach(res; resList)
                            {
                                if(res.resultStatus != ExecStatusType.PGRES_TUPLES_OK &&
                                   res.resultStatus != ExecStatusType.PGRES_COMMAND_OK)
                                {
                                    respond = Respond(new QueryException(res.resultErrorMessage), conn);
                                    rollbackNeeded = true;  
                                    stage = Stage.MoreQueries;                         
                                    failed = true;
                                }
                                res.clear();
                            }
                            if(failed) return;
                        }
                                         
                        if(!hasMoreQueries)
                        {
                            stage = Stage.Finished; 
                            return;
                        }
                        stage = Stage.MoreQueries;
                    }
                    catch(QueryException e)
                    {
                        respond = Respond(e, conn);
                        rollbackNeeded = true;  
                        stage = Stage.MoreQueries;                          
                        return;
                    } 
                    catch (Exception e)
                    {
                        respond = Respond(new QueryException("Internal error: "~e.msg), conn);
                        rollbackNeeded = true; 
                        stage = Stage.MoreQueries; 
                        return;
                    }
                }
            }
        }
        catch(Error err)
        {
            logger.logError(text("Internal unrecoverable error with transaction: ", err.msg));
            logger.logError(transaction.text);
            logger.logError(text("Stack trace: ", err));
            throw err;
        }
    }
       
    void sendRespond()
    {
        sender.send(thisTid, cast(shared)transaction, respond);            
    }
}