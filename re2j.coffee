fs = require 'fs'
_ = require 'lodash'

Parser = require './Parser'
{StringLiteral,
StatusNode,
Connector,
CharacterRange} = require './Node'

class DFATransition
    constructor: (@lower, @upper, @dest) ->
        if not _.isString @upper
            @dest = @upper
            @upper = @lower

    forEachDest: (fn) -> fn @dest

class DfaNode extends StatusNode
    constructor: (@nfaNodes = []) ->
        super()

        @actionId = null
        @isPublicAccpted = false
        @yytypeConfirmed = false

        for node in @nfaNodes
            @isAcceptedState |= node.isAcceptedState

            if node.isAcceptedState
                if @actionId is null
                    @actionId = _.min node.actionId
                else
                    @actionId = _.min [@actionId, _.min node.actionId]

    addEdge: (lower, upper, target) ->
        if not _.isString upper
            @addEdge lower, lower, upper, target
        else
            for edge in @edges
                if edge.lower is lower and edge.upper is upper
                    edge.dest = target
                    return

            @edges.push new DFATransition lower, upper, target

    hasSameTransition: (node) ->
        if node.edges.length isnt @edges.length
            return false

        if node.isAcceptedState
            if node.yytypeConfirmed and not @yytypeConfirmed or node.actionId isnt @actionId
                return false

        for e1 in node.edges
            found = false
            for e2 in @edges
                if e2.upper is e1.upper and e1.lower is e2.lower and e1.dest is e2.dest
                    found = true
                    break
            if not found then return false

        return true

module.exports = class LexerGenerator
    constructor: ->
        @defines = {}
        @action = []
        @newlineStr = '\n'
        @definePromises = []

    addDefine: (name, regex) ->
        if not _.isString name
            for own n, r of name
                @addDefine n, r
        else
            @defines[name] = {regex: new Parser(regex, @, true).parseRegex()}

    addStringDefine: (name, string) ->
        @defines[name] = {regex: new StringLiteral string}

    addAction: (regex, action) ->
        if not _.isString regex
            for own r, a of regex
                @addAction r, a
        else
            @action.push {
                regex: new Parser(regex, @).parseRegex()
                name: action
            }

    addDefinePromise: (name, conn) ->
        @definePromises.push =>
            nfa = @defines[name].regex.generate()
            conn.in.addEdge null, nfa.in
            nfa.out.addEdge null, conn.out

    generateMainNFA: ->
        @mainNFA = new StatusNode()

        for a, i in @action
            a.nfa = a.regex.generate()
            a.nfa.out.actionId.push i
            a.nfa.out.isAcceptedState = true

        promise() for promise in @definePromises

        for a, i in @action
            @mainNFA.addEdge null, a.nfa.in

        @mainNFA.visitAll (node) -> node.simplifyEdges()

    generateMainDFA: ->
        findNodeByClosure = (closure) ->
            for node, i in dStates
                if node.nfaNodes.length isnt closure.length then continue

                found = true
                for v in closure
                    if v not in node.nfaNodes
                        found = false
                        break

                if found then return i

            return -1

        nullClosure = (v) ->
            if _.isArray v then res = v.slice 0 else res = [v]

            i = 0
            loop
                if nullEdge = _.filter(res[i].edges, (e) -> e.lower is null)?[0]
                    for node in nullEdge.dest
                        if node not in res then res.push node

                break unless ++i < res.length

            return res

        makeMoveTable = (set) ->
            table = new CharacterRange []

            for node in set
                for e in node.edges when e.lower isnt null
                    table.editRange e.lower, e.upper, (s) ->
                        s.data = _.uniq s.data.concat e.dest

            return _.filter table.set, (s) -> s.data.length > 0

        unless @mainNFA then @generateMainNFA()

        entrance = @mainNFA
        dStates = [new DfaNode nullClosure entrance]

        i = -1
        while ++i < dStates.length
            moveTable = makeMoveTable dStates[i].nfaNodes
            for set in moveTable
                u = nullClosure set.data
                j = findNodeByClosure u
                if -1 is j
                    dStates.push new DfaNode u
                    j = dStates.length - 1

                dStates[i].addEdge set.lower, set.upper, dStates[j]

        @mainDFA = @minimizeDFACharacterClass @minimizeDFA dStates

    minimizeDFA: (states) ->
        markTransitionTable = (node, table) ->
            for e in node.edges
                table.editRange e.lower, e.upper, (s) ->
                    s.data = e.dest.groupId

        testTransitionTable = (node, table) ->
            for set in table.set
                unreached = true
                for e in node.edges
                    in0 = set.lower <= e.lower <= set.upper
                    in1 = set.lower <= e.upper <= set.upper

                    if in0 or in1 or e.lower <= set.lower and set.upper <= e.upper
                        if e.dest.groupId isnt set.data
                            return false
                    else
                        if set.data isnt null
                            return false

                if unreached and set.data isnt null
                    return false

            return true

        if states.length < 2 then return states[0]

        confirmed = []
        workList = [[], []]
        others = [[]]

        for node in states when node.isAcceptedState
            yytypeConfirmed = true
            node.visitAll (v, search) ->
                if v.isAcceptedState and v.actionId isnt node.actionId
                    yytypeConfirmed = false
                    search.stopAll()

            if node.yytypeConfirmed = yytypeConfirmed
                confirmed.push node

        for node in confirmed
            node.visitAll (v) ->
                if v is node then return

                v.yytypeConfirmed = false
                v.actionId = null

        others[1] = _.remove confirmed, (v) -> not v.yytypeConfirmed
        for node, i in others[1]
            if not node.isAcceptedState
                others.splice i, 1
                others[0].push node

        for node in confirmed
            (workList[0][node.actionId] ?= []).push node

        states[0].visitAll (node, search) ->
            if node in confirmed
                search.stopNode()
            else if node.isAcceptedState
                (workList[0][node.actionId] ?= []).push node
            else
                others[0].push node

        workList[0] = workList[0].concat others
        workList[0] = _.compact workList[0]

        for group in workList[0]
            node.groupId = group[0] for node in group

        f = 0
        reserve = (f) -> if f is 0 then 1 else 0
        loop
            if workList[0].length is workList[1].length then break

            workList[reserve f] = []

            for group in workList[f]
                if workList[f].length < 2
                    workList[reserve f].push group
                    continue

                newGroup = []
                transitionTable = new CharacterRange null
                markTransitionTable group[0], transitionTable

                for node in group[1..group.length - 1]
                    if not testTransitionTable node, transitionTable
                        newGroup.push node

                workList[reserve f].push _.filter group, (s) -> s not in newGroup
                if newGroup.length > 0
                    node.groupId = newGroup[0] for node in newGroup
                    workList[reserve f].push newGroup

            f = reserve f

        entrance = null
        for group in workList[f]
            node = new DfaNode()
            for v in group
                v.groupId = node

                node.isAcceptedState |= v.isAcceptedState
                node.yytypeConfirmed |= v.yytypeConfirmed

                if v.isAcceptedState and (_.isEmpty(node.actionId) or node.actionId > v.actionId)
                    node.actionId = v.actionId

                if v is states[0] then entrance = node

        states = []
        for group in workList[f]
            states.push newNode = group[0].groupId
            for v in group
                for e in v.edges
                    newNode.addEdge e.lower, e.upper, e.dest.groupId

        return entrance

    minimizeDFACharacterClass: (entrance) ->
        loop
            states = []
            entrance.visitAll (v) -> states.push v
            lenA = states.length

            replaced = []

            for n1, i in states[0..states.length - 2]
                if n1 in replaced then continue

                for n2 in states[i + 1..states.length - 1]
                    if n2 in replaced then continue

                    if n2.hasSameTransition n1
                        replaced.push n2

                        n1.isAcceptedState |= n2.isAcceptedState
                        n1.yytypeConfirmed |= n2.yytypeConfirmed
                        n1.actionId = n2.actionId

                        entrance.visitAll (v) ->
                            if v not in replaced
                                for e in v.edges
                                    if e.dest is n2 then e.dest = n1

            lenB = lenA - replaced.length
            if lenB is lenA then break

        return entrance

    generateCode: require './Codegen'

    generateDotData: (path, entrance) ->
        dotFile = "digraph re2j {\n"

        id = 0
        entrance.visitAll (node) -> node.id = id++

        entrance.visitAll (node) ->
            deco = (c) ->
                if c is null then return 'null'

                code = c.charCodeAt 0
                if code >= 0xE000 or 0xD800 <= code <= 0xDFFF
                    return "\\\\u#{code.toString 16}"
                else
                    s = JSON.stringify c
                    s = JSON.stringify s[1..s.length - 2]
                    return s[1..s.length - 2]

            if node.isAcceptedState
                if node.yytypeConfirmed
                    dotFile += "#{node.id} [shape=\"box\"];\n"
                else
                    dotFile += "#{node.id} [shape=\"doublecircle\"];\n"

            for e in node.edges
                e.forEachDest (v) ->
                    if e.upper is e.lower
                        dotFile += "#{node.id} -> #{v.id} [label=\"#{deco e.lower}\"]\n"
                    else
                        dotFile += "#{node.id} -> #{v.id} [label=\"#{deco e.lower} ~ #{deco e.upper}\"]\n"


        dotFile += '}'

        fs.writeFileSync path, dotFile