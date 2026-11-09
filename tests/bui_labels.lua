-- No native window required; exercises caption preparation and publication.
local mua = require 'mua.init'
table.insert(package.loaders, 2, mua.searcher())
local R = require 'mua.runtime'
local Scope = require 'bui.ui.scope'
local Widgets = require 'bui.ui.widgets'
local owner = Scope.new(nil, 'button')
local descriptor = Widgets.catalog.button
local options = R.label('Save')({})
local prepared = Widgets.prepare(descriptor, options)
assert(next(options) == nil)
assert(#prepared == 1 and prepared[1].value == 'Save')
local shown
local record = {
    owner = owner, descriptor = descriptor, kind = descriptor.kind,
    capabilities = {}, node = {},
    native = { BK_set_str = function(_, key, value)
        assert(key == 'text'); shown = value; return 1
    end },
}
Widgets.apply(record, prepared)
assert(shown == 'Save')
assert(R.label_of(record.capabilities) == 'Save')
assert(R.label_of(owner) == 'Save')
Widgets.apply(record, Widgets.prepare(descriptor, 'Enregistrer'))
assert(shown == 'Enregistrer' and R.label_of(record) == shown)
local explicit = R.label('default')({ caption = 'explicit' })
assert(Widgets.prepare(descriptor, explicit)[1].value == 'explicit')
Widgets.apply(record, Widgets.prepare(descriptor, R.label('fallback')({ text = 'Actual' })))
assert(shown == 'Actual' and R.label_of(record.capabilities) == 'Actual')
Widgets.apply(record, Widgets.prepare(descriptor, 'Enregistrer'))
local Check = require 'bui.ui.check'
local operation = R.label('validate caption')(function() end)
local valid, detail = pcall(Check.string, nil, operation)
assert(not valid and detail:find('validate caption', 1, true))
owner.close()
local ok, problem = pcall(owner.check, operation)
assert(not ok and problem:find('Enregistrer activity has ended', 1, true))
assert(problem:find('validate caption', 1, true))
print('BUI labels: passed')
