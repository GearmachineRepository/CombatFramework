--!strict

local WaitHandler = {}

function WaitHandler.Execute(Block: any, _Context: any)
    local Duration = Block.Duration or 0

    if Duration > 0 then
        task.wait(Duration)
    end
end

return WaitHandler