
local DataTables = {
  GET = {}
}


function DataTables._collection( collection_path, options )

  local Collection = require( collection_path )

  local collection = Collection:new( options )

  local result = {}

  local tablerows = {}
  for _, row in ipairs( collection:rows() ) do
    local tablerow = {}
    for _, column in ipairs( options.columns ) do

      --ngx.say( 'column: ', column )
      --ngx.say( inspect( Collection.fieldMapping ) )

      if column == '_action' then
        --ngx.say( inspect( row ) )
        if row.id then
          table.insert( tablerow, '<span id="action_'..row.id..'"></span>' )
        else
          table.insert( tablerow, '<span class="action"></span>' )
        end
      else
        if Collection.fieldMapping[column].location then
          table.insert( tablerow, row[column] )
        elseif Collection.fieldMapping[column].accessor then
          table.insert( tablerow, Collection.fieldMapping[column].accessor( row ) )
        end
      end
    end
    table.insert( tablerows, tablerow )
  end
  result.data = tablerows

  result.recordsTotal = collection:totalCount()

  if options.filter then
    result.recordsFiltered = collection:filteredCount()
  else
    result.recordsFiltered = result.recordsTotal
  end

  return result
end



function DataTables.GET.collection( collection_path, parameters )

  local uri = restfully.arguments()

  local datatable_params = restfully.validate{
    draw = { location = uri.draw, required = true, type = 'integer' },
    columns = { location = uri.columns, required = true, type = {'string'} },
    limit = { location = uri.length, required = true, type = 'integer' },
    offset = { location = uri.start, required = true, type = 'integer' },
    filter = { location = uri.search.value, required = false, type = 'string' },
    filter_regex = { location = uri.search.regex, required = true, type = 'boolean' },
    order_index = { location = uri.order[1].column, required = true, type = 'integer' },
    order_direction = { location = uri.order[1].dir, required = true, type = 'string', values = { 'asc', 'desc' } }
  }

  local options = {
    columns = datatable_params.columns,
    filter = datatable_params.filter,
    offset = datatable_params.offset,
    limit = datatable_params.limit,
    order_by = datatable_params.columns[ datatable_params.order_index + 1],
    order_direction = datatable_params.order_direction,
    conditions = parameters
  }

  --ngx.say( inspect( options.conditions ) )

  restfully.respond( DataTables._collection( collection_path, options ) )
end



return DataTables
