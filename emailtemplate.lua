
--local ObjectModel = require( 'models/object' )
local EmailTemplate = class( 'EmailTemplate', ObjectModel )

EmailTemplate.static.detailMapping = {
  detail_mapping = { 
    required = true, 
    validation = function( value ) 
      if type( value ) ~= 'table' then return false, 'detail_mapping must be a table of tables' end
      local errors = {}
      for name, mapping in pairs( value ) do
        if not mapping.required or not mapping.type then
          table.insert( errors, { name = name, message = "email template mapping '"..name.."' must contain values for 'required' and 'type'" } )
        end
      end
      return #errors == 0, errors
    end 
  }
}

EmailTemplate.static._template_base = 'application/connect.readingandwritingproject.com/emails'


function EmailTemplate:initialize()
  -- override objectmodel's default database connection
end

function EmailTemplate.static:list()
  local templates = wimbly.find( EmailTemplate._template_base )
  
  local results = {} 
  for _, template in ipairs( templates ) do
    table.insert( results, template:match( EmailTemplate._template_base..'/(.*)' ) )
  end
  
  return results
end


function EmailTemplate.static:copy( from, to )
end


function EmailTemplate.static:delete( name )
end


function EmailTemplate.static:fromPath( path )
  local env = {}
  local templet = require( 'templet' )
  
  local template = templet.loadfile( EmailTemplate._template_base..'/'..path )
  
  -- execute template on empty environment to grab detail_mapping
  template( env )
  
  --local success, err = EmailTemplate:validate( env )
  
  --ngx.say( inspect( success ), inspect( err ) )
  
  local success, err = validate.field( 'detail_mapping', env.detail_mapping, EmailTemplate.detailMapping.detail_mapping )

  --ngx.say( inspect( success ), inspect( err ) )
  
  
  if not success then
    return nil, err
  else
  
    --[=[
    local EmailTemplateClass = class( 'EmailTemplateClass', ObjectModel )
    EmailTemplateClass.detailMapping = env.detail_mapping

  
    return {
      
      detail_mapping = env.detail_mapping
      template = template
    }
    --]=]
  end
  
  
end


return EmailTemplate
