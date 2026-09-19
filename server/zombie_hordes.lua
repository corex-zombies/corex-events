-- Event-owned shared lifetimes. Visual hosts never create rewarded zombies.
function CXE_SpawnHorde(state,phase,count,spread)
    local ctx=state.ctx
    if not ctx or ctx.hordesStopped then return false end
    ctx.hordeRequests=ctx.hordeRequests or {}
    local request=ctx.hordeRequests[phase]
    if request then
        if request.status=='accepted' then return true,request.host end
        if request.status~='rejected' then return false end
    else
        request={count=count}; ctx.hordeRequests[phase]=request
    end
    request.status='pending'
    local ok,accepted,host=pcall(function()
        return exports['corex-zombies']:CreateSharedBatch(state.id..':'..phase,state.location,
            request.count,spread,{group=state.id,bucket=0})
    end)
    if ctx.hordesStopped then
        pcall(function() exports['corex-zombies']:ClearSharedGroup(state.id) end)
        return false
    end
    if ok and accepted==true then
        request.status,request.host='accepted',host
        return true,host
    end
    request.status=ok and accepted==false and 'rejected' or 'unknown'
    if request.status=='unknown' then
        CXE_Debug('Error',('Shared horde %s/%s unconfirmed; automatic retry disabled'):format(state.id,phase))
    end
    return false
end

function CXE_ClearHordes(state)
    if state.ctx then state.ctx.hordesStopped=true end
    local ok=pcall(function() exports['corex-zombies']:ClearSharedGroup(state.id) end)
    if not ok then CXE_Debug('Error','Shared horde cleanup unconfirmed: '..state.id) end
end
