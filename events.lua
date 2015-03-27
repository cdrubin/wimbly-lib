
local events = {}

events.fields = { 'type', 'lookup', 'name', 'date', 'grades' }

function events:refresh()
  local red = require( 'lib/rediscache' ).connect()
  local ok, res, err

  res = ngx.location.capture( '/proxy/front/json/events' )

  local event_feed = cjson.decode( res.body )
  local events = {}

  for _, event in ipairs( event_feed ) do
    local key = ''
    local item = nil
    if event.workshop then
      key = 'w:'..event.slug
      item = {
        type = 'workshop',
        name = event.name,
        date = event.date,
        lookup = key,
        grades = event.grades:gsub( ' ', '' )
      }
    elseif event.seminar then
      key = 's:'..event.seminar_id
      item = {
        type = 'seminar',
        name = event.name,
        date = event.date,
        lookup = key,
        grades = event.grades:gsub( ' ', '' )
      }
    elseif event.institute then

      -- get these details from the DB instead
      --[==[
      key = 'i:'..event.shortname
      item = {
        type = 'institute',
        name = event.name,
        date = event.date,
        lookup = key,
        grades = event.grades:gsub( ' ', '' )
      }

      local institute = require( 'model/institute' ):fromName( event.shortname )
      if institute then
        item.forfeit_deadline = institute:get( 'forfeit_deadline' )
        item.payment_expected_in_days = institute:get( 'payment_expected_in_days' )
      end
      --]==]

    end

    res, err = red:hmset( key, item )
  end


  local db = require( 'lib/mysqldatabase' ):connect( 'back.readingandwritingproject.com' )
  --ngx.say( inspect( db ) )
  --ngx.exit( ngx.OK )

  -- add institute accepted group id lookups too for use with purchase orders
  local query = [[

SELECT
  pg_applicant.type,
  pg_applicant.id AS pg_applicant_id,
  pg_accepted.id AS pg_accepted_id,
  pg_withdrawn.id AS pg_withdrawn_id,
  pg_applicant.type,
  pg_applicant.details AS applicant_details,
  pg_accepted.details AS accepted_details,
  pg_withdrawn.details AS withdrawn_details
FROM
  person_groups AS pg_applicant,
  person_groups AS pg_accepted,
  person_groups AS pg_withdrawn
WHERE
  pg_applicant.type = pg_accepted.type
  AND pg_accepted.type = pg_withdrawn.type
  AND pg_applicant.name = 'Applicant'
  AND pg_accepted.name = 'Accepted'
  AND pg_withdrawn.name = 'Withdrawn'

]]

  local institute_rows = db:resultset( query )

  for _, institute in ipairs( institute_rows ) do

    item = {
      type = 'institute',
      lookup = 'i:'..institute.type,
      name = institute.applicant_details.long_name,
      forfeit_deadline = institute.withdrawn_details.forfeit_deadline,
      payment_expected_in_days = institute.accepted_details.payment_expected_in_days,
      withdrawal_penalty = institute.withdrawn_details.withdrawal_penalty
    }

    local dates = institute.applicant_details.event_dates
    if not dates then dates = institute.applicant_details.start_date end
    if dates then
      item.date = dates:match( '^(%d%d%d%d%-%d%d%-%d%d)' )
    end

    res, err = red:hmset( 'i:'..institute.type, item )

    item.group = 'Applicant'
    res, err = red:hmset( 'pg:'..institute.pg_applicant_id, item )

    item.group = 'Accepted'
    res, err = red:hmset( 'pg:'..institute.pg_accepted_id, item )

    item.group = 'Withdrawn'
    res, err = red:hmset( 'pg:'..institute.pg_withdrawn_id, item )
  end

  res, err = red:set( 'events_last_refreshed', ngx.now() )
  red:close()
end


function events:_retrieve( key_start )
  local red = require( 'lib/rediscache' ).connect()

  local ok, res, err

  res, err = red:get( 'events_last_refreshed' )

  if res ~= ngx.null then

    -- currently return 's'eminars, 'i'nstitutes and 'w'orkshops
    keys, err = red:keys( '['..key_start..']:*' )
    local items = {}

    for _, key in ipairs( keys ) do
      local item = {}
      res, err = red:hmget( key, unpack( events.fields ) )
      for index, field in ipairs( res ) do
        item[ events.fields[index] ] = res[index]
      end
      table.insert( items, item )
    end
    return items
  else
    -- refresh the cache
    self:refresh()
    return self:_retrieve( key_start )
  end

end


function events:all()
  return self:_retrieve( 'isw' )
end


function events:institutes()
  return self:_retrieve( 'i' )
end


function events:workshops()
  return self:_retrieve( 'w' )
end


function events.seminars()
  return self:_retrieve( 's' )
end


function events:get( lookup )
  local red = require( 'lib/rediscache' ).connect()

  local ok, res, err

  if lookup then

    res, err = red:get( 'events_last_refreshed' )
    if res ~= ngx.null and lookup then

      res, err = red:hgetall( lookup )

      if res and #res > 0 then

        local item = {}

        for i = 1, #res, 2 do
          item[res[i]] = res[i+1]
        end

        return item

      end
    else
      self:refresh()
      return self:get( lookup )
    end

  end

end

return events
