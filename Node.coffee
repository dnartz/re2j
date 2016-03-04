_ = require 'lodash'

class Transition
    constructor: (@lower, @upper, @dest...) ->
        @isRangeEdge = @lower isnt @upper

    forEachDest: (fn) -> _.forEach @dest, fn

exports.CharacterRange = class CharacterRange
    constructor: (initData, lower = '\u0000', upper = '\uffff') ->
        @set = [{lower: lower, upper: upper, data: initData}]

    prevChar: (c) -> String.fromCharCode c.charCodeAt(0) - 1

    nextChar: (c) -> String.fromCharCode c.charCodeAt(0) + 1

    editPoint: (p, fn) -> @editRange p, p, fn

    editRange: (lower, upper, fn) ->
        i = 0
        loop
            in0 = @set[i].lower <= lower <= @set[i].upper
            in1 = @set[i].lower <= upper <= @set[i].upper

            if in0 and not in1
                if @set[i].lower is lower
                    fn @set[i++]
                else if @set[i].upper is lower
                    @set.splice i + 1, 0, {lower: @nextChar(upper), upper: @set[i].upper, data: _.clone(@set[i].data)}
                    @set[i].upper = upper
                    fn @set[i]
                    i += 2
                else
                    @set.splice i + 1, 0, {lower: lower, upper: @set[i].upper, data: _.clone(@set[i].data)}
                    @set[i].upper = @prevChar lower
                    fn @set[i + 1]
                    i += 2

            else if in0 and in1
                if @set[i].lower < lower
                    if upper < @set[i].upper
                        @set.splice i + 1, 0, {lower: lower, upper: upper, data: _.clone(@set[i].data)}
                        @set.splice i + 2, 0, {lower: @nextChar(upper), upper: @set[i].upper, data: _.clone(@set[i].data)}
                    else # if upper is @set[i].upper
                        @set.splice i + 1, 0, {lower: lower, upper: upper, data: _.clone(@set[i].data)}

                    @set[i].upper = @prevChar lower
                    return fn @set[i + 1]

                else # if @set[i].lower is lower
                    if upper < @set[i].upper
                        @set.splice i + 1, 0, {lower: @nextChar(upper), upper: @set[i].upper, data: _.clone(@set[i].data)}
                        @set[i].upper = upper

                    return fn @set[i]

            else if not in0 and in1
                if @set[i].upper is upper
                    fn @set[i++]
                else if @set[i].lower is upper
                    @set.splice i + 1, 0, {lower: @nextChar(upper), upper: @set[i].upper, data: _.clone(@set[i].data)}
                    @set[i].upper = upper
                    return fn @set[i]
                else
                    @set.splice i + 1, 0, {lower: @nextChar(upper), upper: @set[i].upper, data: _.clone(@set[i].data)}
                    @set[i].upper = upper
                    return fn @set[i]

            else if lower <= @set[i].lower and @set[i].upper <= upper
                fn @set[i++]

            else
                i++

            break unless i < @set.length

exports.StatusNode = class StatusNode
    constructor: ->
        @id = null
        @edges = []
        @actionId = []
        @isAcceptedState = false

    addEdge: (lower, upper, targets...) ->
        if lower is null
            if upper isnt null then targets.push upper

            for edge in @edges
                if edge.lower is null
                    edge.dest = _.uniq edge.dest.concat targets
                    return

            @edges.push new Transition null, null, targets...
        else if not _.isString upper
            @addEdge lower, lower, upper, targets...
        else
            for edge in @edges
                if edge.lower <= lower <= edge.upper or edge.lower <= upper <= edge.upper
                    edge.dest = _.uniq edge.dest.concat targets
                    return

            @edges.push new Transition lower, upper, targets...

    simplifyEdges: ->
        isSubset = (a, b) ->
            for c in a
                if c not in b then return false

            return true

        if @edges.length < 2 then return

        edges = []
        for e1 in @edges
            edges.push e1
            for e2 in @edges
                if e1 is e2 then continue

                if e2.lower <= e1.lower <= e1.upper <= e2.upper and isSubset e1.dest, e2.dest
                    edges.pop()
                    break

        @edges = edges

    visitAll: (fn) ->
        list = [@]
        visited = []
        stop = false

        while list.length > 0
            stopNode = false
            visited.push v = list.shift()

            fn v, {
                stopAll: -> stop= true
                stopNode: -> stopNode = true
            }
            if stop then return

            if stopNode then continue

            for e in v.edges
                e.forEachDest (node) ->
                    if node not in visited and node not in list then list.push node

exports.Connector = class Connector
    constructor: (@in = new StatusNode(), @out = new StatusNode()) ->
        @isTailingContext = false

exports.Group = class Group
    constructor: (@regex) ->

    generate: -> @regex.generate()

exports.Alternative = class Alternative
    constructor: (atom) -> @atoms = [atom]

    merge: (alt) ->
        @atoms = @atoms.concat alt.atoms

    generate: ->
        conn = new Connector()

        for atom in @atoms
            res = atom.generate()
            conn.in.addEdge null, res.in
            res.out.addEdge null, conn.out

        return conn

exports.CharacterClass = class CharacterClass
    constructor: (@inverted, @single, @ranges) ->

    generate: ->
        conn = new Connector()

        if @inverted
            cRange = new CharacterRange true
            cRange.editPoint(ch, (p) -> p.data = false) for ch in @single
            cRange.editRange(range[0], range[1], (p) -> p.data = false) for range in @ranges

            _.forEach cRange.set, (s) ->
                if s.data
                    conn.in.addEdge s.lower, s.upper, conn.out
        else
            for ch in @single
                conn.in.addEdge ch, conn.out

            for range in @ranges
                conn.in.addEdge range[0], range[1], conn.out

        return conn

exports.ZeroOrMore = class ZeroOrMore
    constructor: (@atom) ->

    generate: ->
        gAtom = @atom.generate()
        gAtom.in.addEdge null, gAtom.out
        gAtom.out.addEdge null, gAtom.in

        return gAtom


exports.OneOrMore = class OneOrMore
    constructor: (@atom) ->

    generate: ->
        gAtom = @atom.generate()
        gAtom.out.addEdge null, gAtom.in

        return gAtom

exports.Optional = class Optional
    constructor: (@atom) ->

    generate: ->
        gAtom = @atom.generate()
        gAtom.in.addEdge null, gAtom.out

        return gAtom

exports.Repeat = class Repeat
    constructor: (@atom, @lower, @least = false, @upper = null) ->
        @exactly = not @least
        @lower = parseInt @lower, 10
        if @upper then @upper = parseInt @upper, 10

    generate: ->
        gAtoms = _.cloneDeep(@atom).generate() for i in [1..(if @upper then @upper else @lower)]
        for conn, i in gAtoms
            if i < @lower - 1
                gAtoms[i].out.addEdge null, gAtoms[i + 1].in

        conn = new Connector gAtoms[0], _.last gAtoms
        if not @exactly
            conn.out.addEdge null, conn.in

        # {n} {n, }
        if @upper is null
            return conn
        else
            for i in [@lower - 1..@upper - 1]
                gAtoms[i].out.addEdge null, conn.out


exports.Combination = class Combination
    constructor: (atoms...) -> @atoms = atoms

    generate: ->
        gAtoms = @atoms.map (a) ->
            a.generate()
        for conn, i in gAtoms
            if i isnt 0 then gAtoms[i - 1].out.addEdge null, conn.in
            if i isnt gAtoms.length - 1 then conn.out.addEdge null, gAtoms[i + 1].in

        return new Connector gAtoms[0].in, gAtoms[gAtoms.length - 1].out

exports.TailingContext = class TailingContext
    constructor: (@match, @cond) ->

    generate: ->
        gMatch = @match.generate()
        gCond = @cond.generate()
        gCond.isTailingContext = true

        gMatch.out.addEdge null, gCond.in

        new Connector gMatch.in, gCond.out

exports.Define = class Define
    constructor: (@lexerGenerator, @name) ->

    generate: ->
        conn = new Connector()
        @lexerGenerator.addDefinePromise @name, conn

        return conn

exports.StringLiteral = class StringLiteral
    constructor: (@literal) ->

    generate: ->
        path = for i in [0..@literal.length]
            new StatusNode()
        for ch, i in @literal
            path[i].addEdge ch, path[i + 1]

        return new Connector path[0], path[path.length - 1]

exports.MatchAny = class MatchAny
    generate: ->
        conn = new Connector()
        conn.in.addRange '\u0000', '\uffff', conn.out

        return conn
