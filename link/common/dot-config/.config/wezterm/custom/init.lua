local modules = {'keys', 'ui'}

function apply_to_config(config)
    for i, module in ipairs(modules) do
        require('custom.' .. module).apply_to_config(config)
    end
end

return {
    apply_to_config = apply_to_config
}
