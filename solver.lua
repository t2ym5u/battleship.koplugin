-- ---------------------------------------------------------------------------
-- solver.lua — no-trial logic solver for Battleship (Bimaru)
--
-- Solves a puzzle the way a player does, one deduction at a time, and never
-- by "assume X, find a contradiction". Whatever it fills in follows from the
-- clues, so a puzzle it solves completely has exactly one solution.
--
--   local Solver = require("solver")   -- (loaded by path from board.lua)
--   local ok, state, stats = Solver.solve(n, row_clues, col_clues, init, max_tier)
--
-- init:     flat array, index (r-1)*n + c, values UNK (0) / WATER (1) / SHIP (2)
--           (the revealed cells; it is not modified).
-- max_tier: the hardest family of deductions allowed:
--   0  basic   -- line counts (a full row is water, a row with exactly as
--                 many free cells as missing ships is ships), water on the
--                 diagonals of a ship, ships are straight, the battleship
--                 is the longest ship;
--   1  fleet   -- count the finished ships: once every ship of a size is
--                 found, a run of that size is finished and a run that
--                 cannot be that size must grow;
--   2  advanced -- list where the remaining ships of each size can still
--                 go (a cell no ship can reach is water, a cell every
--                 placement uses is a ship, ...).
-- Returns solved (bool), the final state, and stats
--   { [0] = basic cells, [1] = fleet steps, [2] = advanced steps, bad = contradiction }.
-- ---------------------------------------------------------------------------

local UNK, WATER, SHIP = 0, 1, 2

local Solver = { UNK = UNK, WATER = WATER, SHIP = SHIP }

-- Standard fleet, as count per length.
Solver.FLEET = { [1] = 4, [2] = 3, [3] = 2, [4] = 1 }
local MAXLEN = 4

function Solver.solve(n, rows, cols, init, max_tier, fleet)
    fleet = fleet or Solver.FLEET
    max_tier = max_tier or 2
    local NN = n * n
    local st = {}
    for i = 1, NN do st[i] = init[i] or UNK end
    local stats = { [0] = 0, [1] = 0, [2] = 0, bad = false }
    local bad = false

    -- Out of the grid counts as water.
    local function get(r, c)
        if r < 1 or r > n or c < 1 or c > n then return WATER end
        return st[(r - 1) * n + c]
    end

    local changed
    local function set(r, c, v)
        if r < 1 or r > n or c < 1 or c > n then
            if v == SHIP then bad = true end
            return
        end
        local i = (r - 1) * n + c
        local cur = st[i]
        if cur == UNK then
            st[i] = v
            changed = changed + 1
        elseif cur ~= v then
            bad = true
        end
    end

    -- -----------------------------------------------------------------------
    -- Tier 0: basic
    -- -----------------------------------------------------------------------
    local function lineCounts()
        for r = 1, n do
            local s, u = 0, 0
            local base = (r - 1) * n
            for c = 1, n do
                local v = st[base + c]
                if v == SHIP then s = s + 1 elseif v == UNK then u = u + 1 end
            end
            if s > rows[r] or s + u < rows[r] then bad = true; return end
            if u > 0 then
                if s == rows[r] then
                    for c = 1, n do if st[base + c] == UNK then set(r, c, WATER) end end
                elseif s + u == rows[r] then
                    for c = 1, n do if st[base + c] == UNK then set(r, c, SHIP) end end
                end
            end
        end
        for c = 1, n do
            local s, u = 0, 0
            for r = 1, n do
                local v = st[(r - 1) * n + c]
                if v == SHIP then s = s + 1 elseif v == UNK then u = u + 1 end
            end
            if s > cols[c] or s + u < cols[c] then bad = true; return end
            if u > 0 then
                if s == cols[c] then
                    for r = 1, n do if st[(r - 1) * n + c] == UNK then set(r, c, WATER) end end
                elseif s + u == cols[c] then
                    for r = 1, n do if st[(r - 1) * n + c] == UNK then set(r, c, SHIP) end end
                end
            end
        end
    end

    local function shipNeighbours()
        for r = 1, n do
            for c = 1, n do
                if st[(r - 1) * n + c] == SHIP then
                    set(r - 1, c - 1, WATER); set(r - 1, c + 1, WATER)
                    set(r + 1, c - 1, WATER); set(r + 1, c + 1, WATER)
                    -- Ships are straight.
                    if get(r, c - 1) == SHIP or get(r, c + 1) == SHIP then
                        set(r - 1, c, WATER); set(r + 1, c, WATER)
                    end
                    if get(r - 1, c) == SHIP or get(r + 1, c) == SHIP then
                        set(r, c - 1, WATER); set(r, c + 1, WATER)
                    end
                end
            end
        end
    end

    -- A run as long as the longest ship is a whole ship.
    local function longRuns(maxlen)
        for r = 1, n do
            local c = 1
            while c <= n do
                if st[(r - 1) * n + c] == SHIP then
                    local e = c
                    while e < n and st[(r - 1) * n + e + 1] == SHIP do e = e + 1 end
                    local len = e - c + 1
                    if len > maxlen then bad = true; return end
                    if len == maxlen and len > 1 then set(r, c - 1, WATER); set(r, e + 1, WATER) end
                    c = e + 1
                else
                    c = c + 1
                end
            end
        end
        for c = 1, n do
            local r = 1
            while r <= n do
                if st[(r - 1) * n + c] == SHIP then
                    local e = r
                    while e < n and st[e * n + c] == SHIP do e = e + 1 end
                    local len = e - r + 1
                    if len > maxlen then bad = true; return end
                    if len == maxlen and len > 1 then set(r - 1, c, WATER); set(e + 1, c, WATER) end
                    r = e + 1
                else
                    r = r + 1
                end
            end
        end
    end

    local fleet_max = 0
    for L, k in pairs(fleet) do if k > 0 and L > fleet_max then fleet_max = L end end

    local function tier0()
        local total = 0
        repeat
            changed = 0
            lineCounts()
            if not bad then shipNeighbours() end
            if not bad then longRuns(fleet_max) end
            total = total + changed
        until changed == 0 or bad
        return total
    end

    -- -----------------------------------------------------------------------
    -- Runs of known ship cells (shared by tiers 1 and 2)
    -- -----------------------------------------------------------------------
    -- Each run: { r, c, len, dir ("h", "v" or nil for a lone cell), complete }.
    local function findRuns()
        local runs = {}
        local seen = {}
        for r = 1, n do
            for c = 1, n do
                local i = (r - 1) * n + c
                if st[i] == SHIP and not seen[i] then
                    local run
                    if get(r, c + 1) == SHIP then
                        local e = c
                        while get(r, e + 1) == SHIP do e = e + 1; seen[(r - 1) * n + e] = true end
                        run = { r = r, c = c, len = e - c + 1, dir = "h",
                                complete = get(r, c - 1) == WATER and get(r, e + 1) == WATER }
                    elseif get(r + 1, c) == SHIP then
                        local e = r
                        while get(e + 1, c) == SHIP do e = e + 1; seen[(e - 1) * n + c] = true end
                        run = { r = r, c = c, len = e - r + 1, dir = "v",
                                complete = get(r - 1, c) == WATER and get(e + 1, c) == WATER }
                    else
                        run = { r = r, c = c, len = 1,
                                complete = get(r - 1, c) == WATER and get(r + 1, c) == WATER
                                       and get(r, c - 1) == WATER and get(r, c + 1) == WATER }
                    end
                    seen[i] = true
                    runs[#runs + 1] = run
                end
            end
        end
        return runs
    end

    local function remainingFleet(runs)
        local rem = {}
        for L = 1, MAXLEN do rem[L] = fleet[L] or 0 end
        for _, run in ipairs(runs) do
            if run.complete then
                if run.len > MAXLEN or (rem[run.len] or 0) <= 0 then bad = true; return rem end
                rem[run.len] = rem[run.len] - 1
            end
        end
        return rem
    end

    -- -----------------------------------------------------------------------
    -- Tier 1: fleet counting
    -- -----------------------------------------------------------------------
    local function tier1()
        changed = 0
        local runs = findRuns()
        local rem = remainingFleet(runs)
        if bad then return 0 end
        local lmax = 0
        for L = MAXLEN, 1, -1 do if rem[L] > 0 then lmax = L; break end end
        for _, run in ipairs(runs) do
            if not run.complete then
                local r, c, len = run.r, run.c, run.len
                if len > lmax then bad = true; return 0 end
                if len == lmax then
                    -- As long as the longest ship still missing: finished.
                    if run.dir == "h" then
                        set(r, c - 1, WATER); set(r, c + len, WATER)
                    elseif run.dir == "v" then
                        set(r - 1, c, WATER); set(r + len, c, WATER)
                    else
                        set(r - 1, c, WATER); set(r + 1, c, WATER)
                        set(r, c - 1, WATER); set(r, c + 1, WATER)
                    end
                elseif rem[len] == 0 then
                    -- No ship of this size left: it must grow, and if one
                    -- side is closed it grows on the other.
                    if run.dir == "h" then
                        if get(r, c - 1) == WATER then set(r, c + len, SHIP)
                        elseif get(r, c + len) == WATER then set(r, c - 1, SHIP) end
                    elseif run.dir == "v" then
                        if get(r - 1, c) == WATER then set(r + len, c, SHIP)
                        elseif get(r + len, c) == WATER then set(r - 1, c, SHIP) end
                    else
                        local open, k = nil, 0
                        for _, d in ipairs{ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } } do
                            if get(r + d[1], c + d[2]) ~= WATER then open = d; k = k + 1 end
                        end
                        if k == 0 then bad = true; return 0 end
                        if k == 1 then set(r + open[1], c + open[2], SHIP) end
                    end
                end
                if changed > 0 or bad then return changed end
            end
        end
        return changed
    end

    -- -----------------------------------------------------------------------
    -- Tier 2: where can the remaining ships still go
    -- -----------------------------------------------------------------------
    -- A placement of a ship of length L is stored as three numbers in flat
    -- lists (row, column, 1 = horizontal / 0 = vertical): no table per
    -- placement, this runs many times per generated puzzle.
    local cnt, rcnt = {}, {}
    for i = 1, NN do cnt[i] = 0; rcnt[i] = 0 end

    -- All placements of a ship of length L consistent with the grid: no
    -- water inside, no ship touching it from outside, room left in the
    -- row and column counts, and not a ship already found complete.
    local function placements(L, rs, cs, out)
        local k0 = 0
        for dir = 1, (L > 1 and 2 or 1) do
            local horiz = dir == 1
            local dr, dc = horiz and 0 or 1, horiz and 1 or 0
            local rmax = horiz and n or n - L + 1
            local cmax = horiz and n - L + 1 or n
            for r = 1, rmax do
                for c = 1, cmax do
                    local ok, unk = true, 0
                    for k = 0, L - 1 do
                        local rr, cc = r + dr * k, c + dc * k
                        local v = st[(rr - 1) * n + cc]
                        if v == WATER then ok = false; break end
                        if v == UNK then
                            unk = unk + 1
                            -- the crossing line must have room for it
                            if horiz then
                                if cs[cc] + 1 > cols[cc] then ok = false; break end
                            elseif rs[rr] + 1 > rows[rr] then ok = false; break end
                        end
                    end
                    if ok then
                        if horiz then
                            if rs[r] + unk > rows[r] then ok = false end
                        elseif cs[c] + unk > cols[c] then ok = false end
                    end
                    if ok then
                        local r2, c2 = r + dr * (L - 1), c + dc * (L - 1)
                        local allwater = true
                        for rr = r - 1, r2 + 1 do
                            if rr >= 1 and rr <= n then
                                for cc = c - 1, c2 + 1 do
                                    if cc >= 1 and cc <= n
                                        and (rr < r or rr > r2 or cc < c or cc > c2) then
                                        local v = st[(rr - 1) * n + cc]
                                        if v == SHIP then ok = false; break end
                                        if v == UNK then allwater = false end
                                    end
                                end
                                if not ok then break end
                            end
                        end
                        -- a finished ship is already counted
                        if ok and unk == 0 and allwater then ok = false end
                    end
                    if ok then
                        out[k0 + 1] = r; out[k0 + 2] = c; out[k0 + 3] = horiz and 1 or 0
                        k0 = k0 + 3
                    end
                end
            end
        end
        for k = #out, k0 + 1, -1 do out[k] = nil end
        return k0 / 3
    end

    local function setIdx(i, v)
        set(math.floor((i - 1) / n) + 1, (i - 1) % n + 1, v)
    end

    -- Adds one placement to the cnt (cells) / rcnt (surrounding water) tallies.
    local function tally(L, r, c, h)
        local r2 = r + (h == 1 and 0 or L - 1)
        local c2 = c + (h == 1 and L - 1 or 0)
        for rr = r - 1, r2 + 1 do
            if rr >= 1 and rr <= n then
                for cc = c - 1, c2 + 1 do
                    if cc >= 1 and cc <= n then
                        local i = (rr - 1) * n + cc
                        if rr < r or rr > r2 or cc < c or cc > c2 then
                            rcnt[i] = rcnt[i] + 1
                        else
                            cnt[i] = cnt[i] + 1
                        end
                    end
                end
            end
        end
    end

    -- After tallying `total` placements: cells in all of them are ships,
    -- cells around all of them are water. Resets the tallies.
    local function settle(total)
        for i = 1, NN do
            if total > 0 and st[i] == UNK then
                if cnt[i] == total then setIdx(i, SHIP)
                elseif rcnt[i] == total then setIdx(i, WATER) end
            end
            cnt[i] = 0; rcnt[i] = 0
        end
    end

    local cand, ncand = {}, {}
    for L = 1, MAXLEN do cand[L] = {} end

    local function tier2()
        changed = 0
        local runs = findRuns()
        local rem = remainingFleet(runs)
        if bad then return 0 end
        local rs, cs = {}, {}
        for i = 1, n do rs[i] = 0; cs[i] = 0 end
        for r = 1, n do
            for c = 1, n do
                if st[(r - 1) * n + c] == SHIP then rs[r] = rs[r] + 1; cs[c] = cs[c] + 1 end
            end
        end
        for L = MAXLEN, 1, -1 do
            ncand[L] = 0
            if rem[L] > 0 then
                ncand[L] = placements(L, rs, cs, cand[L])
                if ncand[L] < rem[L] then bad = true; return 0 end
            end
        end
        -- (a) As many places as ships of that size: all are used.
        --     One ship of that size left: what all its places share.
        for L = MAXLEN, 1, -1 do
            if rem[L] > 0 and (ncand[L] == rem[L] or rem[L] == 1) then
                local p = cand[L]
                for k = 0, ncand[L] - 1 do tally(L, p[3 * k + 1], p[3 * k + 2], p[3 * k + 3]) end
                if ncand[L] == rem[L] then
                    for i = 1, NN do
                        if cnt[i] > 0 and st[i] == UNK then setIdx(i, SHIP) end
                        cnt[i] = 0; rcnt[i] = 0
                    end
                else
                    settle(ncand[L])
                end
                if changed > 0 or bad then return changed end
            end
        end
        -- (b) A cell no remaining ship can cover is water.
        for L = 1, MAXLEN do
            if rem[L] > 0 then
                local p = cand[L]
                for k = 0, ncand[L] - 1 do tally(L, p[3 * k + 1], p[3 * k + 2], p[3 * k + 3]) end
            end
        end
        for i = 1, NN do
            if st[i] == UNK and cnt[i] == 0 then setIdx(i, WATER) end
            cnt[i] = 0; rcnt[i] = 0
        end
        if changed > 0 or bad then return changed end
        -- (c) An unfinished run of ship cells: what every ship that could
        --     contain it shares.
        for _, run in ipairs(runs) do
            if not run.complete then
                local r0, c0 = run.r, run.c
                local total = 0
                for L = run.len, MAXLEN do
                    if rem[L] > 0 then
                        local p = cand[L]
                        for k = 0, ncand[L] - 1 do
                            local r, c, h = p[3 * k + 1], p[3 * k + 2], p[3 * k + 3]
                            local hit
                            if h == 1 then hit = r == r0 and c0 >= c and c0 <= c + L - 1
                            else hit = c == c0 and r0 >= r and r0 <= r + L - 1 end
                            if hit then tally(L, r, c, h); total = total + 1 end
                        end
                    end
                end
                if total == 0 then bad = true; return 0 end
                settle(total)
                if changed > 0 or bad then return changed end
            end
        end
        return 0
    end

    -- -----------------------------------------------------------------------
    -- Main loop: basic deductions to a standstill, then one harder step.
    -- -----------------------------------------------------------------------
    while not bad do
        stats[0] = stats[0] + tier0()
        if bad then break end
        local done = true
        for i = 1, NN do if st[i] == UNK then done = false; break end end
        if done then break end
        local progressed = false
        if max_tier >= 1 and tier1() > 0 then
            stats[1] = stats[1] + 1; progressed = true
        end
        if not progressed and not bad and max_tier >= 2 and tier2() > 0 then
            stats[2] = stats[2] + 1; progressed = true
        end
        if not progressed then break end
    end

    stats.bad = bad
    if bad then return false, st, stats end
    for i = 1, NN do if st[i] == UNK then return false, st, stats end end
    -- Every cell decided: make sure the fleet really is the fleet (the line
    -- rules alone don't check the ship sizes).
    local runs = findRuns()
    local rem = remainingFleet(runs)
    if bad then stats.bad = true; return false, st, stats end
    for L = 1, MAXLEN do
        if rem[L] ~= 0 then stats.bad = true; return false, st, stats end
    end
    return true, st, stats
end

return Solver
