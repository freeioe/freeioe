-- Ordered Table
-- Written by Rici Lake. The author disclaims all rights and responsibilities,
-- and relinquishes the software below to the public domain.
-- Have fun with it.
--
-- The function Ordered creates a table which can iterate in order of its
-- entries. You'll need to modify pairs as indicated on the Lua wiki
-- (GeneralizedPairsAndIpairs) in order to use this feature.
--
-- Since stock Lua does not have constructors, you cannot "seed" the
-- table with an initializer. A patch for this is forthcoming; this function
-- was extracted from the tests for that patch.
--
-- The table does not allow deletion, so it might not be appropriate
-- for all cases. You can set a key to nil, which removes it from
-- the iteration, but the key is actually permanently in the table,
-- and setting it to a new value will restore it to its original place
-- in the table. Obviously, that's not ideal, but it was simple and
-- efficient, and it is always possible to compact a table by copying it.
--
-- Rather than use what seems to be the classic implementation, with
-- three tables: <key->ordinal, ordinal->key, ordinal->value>, we
-- use a regular key->value table, with an auxiliary linked list
-- key->nextkey.
-- 
-- The advantage of this setup is that we don't need to invoke a
-- metamethod for any case other than setting a new key (or a key
-- which has been previously set to nil), which is a significant
-- speed-up. It also makes it easy to implement the stability
-- guarantee. The disadvantage is that there is effectively a
-- memory-leak.
--
-- The table is fully stable; during an iteration, you can perform
-- an arbitrary modification (since keys are not ever actually deleted).
 
local function Ordered()
  -- nextkey and firstkey are used as markers; nextkey[firstkey] is
  -- the first key in the table, and nextkey[nextkey] is the last key.
  -- nextkey[nextkey[nextkey]] should always be nil.
 
  local key2val, nextkey, firstkey = {}, {}, {}
  nextkey[nextkey] = firstkey
 
  local function onext(self, key)
    while key ~= nil do
      key = nextkey[key]
      local val = self[key]
      if val ~= nil then return key, val end
    end
  end
 
  -- To save on tables, we use firstkey for the (customised)
  -- metatable; this line is just for documentation
  local selfmeta = firstkey
 
  -- record the nextkey table, for routines lacking the closure
  selfmeta.__nextkey = nextkey
 
  -- setting a new key (might) require adding the key to the chain
  function selfmeta:__newindex(key, val)
    rawset(self, key, val)
    if nextkey[key] == nil then -- adding a new key
      nextkey[nextkey[nextkey]] = key
      nextkey[nextkey] = key
    end
  end
 
  -- if you don't have the __pairs patch, use this:
  -- local _p = pairs; function pairs(t, ...)
  --    return (getmetatable(t).__pairs or _p)(t, ...) end
  function selfmeta:__pairs() return onext, self, firstkey end
 
  return setmetatable(key2val, selfmeta)
end

return Ordered
