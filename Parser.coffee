{
Group,
Alternative,
CharacterClass,
ZeroOrMore,
OneOrMore,
Optional,
Repeat,
Combination,
TailingContext,
Define,
MatchAny,
StringLiteral
} = require './Node'

module.exports = class RegexParser

    constructor: (@regex, @lexerGenerator, @noTailingContext = false) ->
        if @regex.length is 0
            throw new Error 'Unexpected null string.'

        @i = 0

    parseRegex: ->
        combination = new Combination()
        while atom = @parseAtom()
            combination.atoms.push atom

        if combination.atoms.length is 1
            return combination.atoms[0]
        else
            return combination

    parseAtom: ->
        if @skipSpace() and @isEnd() then return null

        atom = null
        switch @regex[@i]
            when '('
                atom = @parseGroup()

            when ')'
                return null

            when '['
                atom = @parseCharacterClass()

            when '.'
                @i++
                atom = new MatchAny()

            when '"', "'"
                atom = @parseStringLiteral()

            else
                # match names
                if atom = @regex[@i...].match(/^[A-Za-z_][A-Za-z_0-9]*/)?[0]
                    @i += atom.length
                    atom = new Define @lexerGenerator, atom
                else
                    throw @unexpectedCharacter()

        return @parseAtomSuffix atom


    parseAtomSuffix: (atom) ->

        isInstanceOf = (l) ->
            r = false
            r |= atom instanceof p for p in l
            return r

        if @skipSpace() and @isEnd() then return atom

        switch @regex[@i]
            when '*'
                @i++
                unless isInstanceOf [ZeroOrMore, OneOrMore, Optional, Repeat]
                    return @parseAtomSuffix new ZeroOrMore atom
                else
                    throw @unexpectedCharacter()

            when '+'
                @i++
                unless isInstanceOf [Optional, OneOrMore]
                    return @parseAtomSuffix new OneOrMore atom
                else
                    throw @unexpectedCharacter()

            when '?'
                @i++
                return @parseAtomSuffix new Optional atom

            when '|'
                return @parseAlternative atom

            when '/'
                if @noTailingContext
                    throw @unexpectedCharacter()
                else
                    return @parseTrailingContext atom

            when '{'
                if isInstanceOf [ZeroOrMore, OneOrMore, Repeat]
                    return @parseRepeat atom
                else
                    throw @unexpectedCharacter()

            when ')', ']', '(', '[', '"'
                return atom

            else
                if /_|[A-Z]|[a-z]/.test @regex[@i]
                    return atom
                else
                    return @parseAtomSuffix atom


    parseGroup: ->
        iLeft = @i++
        r = @parseRegex()

        if @regex[@i] isnt ')'
            throw @unmatchedError iLeft
        else
            @i++
            return new Group r

    parseCharacter: ->
        switch @regex[@i]
            when '\\'
                if @isEnd @i + 1 then throw @unexpectedCharacter()

                @i += 2
                if /['"\\/bfnrt]/.test @regex[@i - 1]
                    return eval "'\\" + @regex[@i - 1] + "'"
                else if @regex[@i - 1] is 'u' and @regex.length - i >= 4
                    slice = @regex[i..i + 3]

                    if slice.match(/^([0-9A-Za-z]{4})$/)?[0] is slice
                        return eval "\"\\u#{slice}\""
                    else
                        throw @unexpectedCharacter()
                else
                    return @regex[@i - 1]

            when '"', "'"
                return null

            else
                return @regex[@i++]


    parseCharacterClass: ->
        class RangeError extends Error
            constructor: (regex, i, lower, upper) ->
                mark = Array(i).join(' ') + Array(lower + 1).join('^') + ' ' + Array(upper + 1).join '^'

                @name = 'RangeError'
                @message = "error: range out of order in character class\n#{regex}\n#{mark}\n"

        single = []
        ranges = []

        @i++
        if inverted = @regex[@i] is '^' then @i++

        while @regex[@i] isnt ']' and @i < @regex.length - 1
            c = @parseCharacter()
            if @regex[@i] is '-'
                @i++
                if @isEnd()
                    throw @unexpectedCharacter()
                else
                    c1 = @parseCharacter()

                if c1.charCodeAt(0) >= c.charCodeAt 0
                    ranges.push [c, c1]
                else
                    throw new RangeError @regex, @i, c.length, c1.length
            else
                single.push c

        if @regex[@i++] isnt ']' then throw @unexpectedCharacter()

        return new CharacterClass inverted, single, ranges

    parseStringLiteral: ->
        iLeft = @i
        match = @regex[@i++]

        s = ''
        while c = @parseCharacter()
            s += c

        if @isEnd()
            throw @unexpectedEnd()
        else if match isnt @regex[@i++]
            throw @unmatchedError iLeft, match
        else
            return new StringLiteral s

    parseAlternative: (leftmostAtom) ->
        @i++
        alt = new Alternative leftmostAtom
        if a = @parseAtom()
            if a instanceof Alternative
                alt.merge a
            else
                alt.atoms.push a

            return alt
        else
            throw @unexpectedCharacter()

    parseRepeat: (atom) ->
        NUMBER = /^[1-9][0-9]*/

        iLeft = @i++
        unless lower = @regex[@i...].match(NUMBER)?[0]
            throw @unexpectedCharacter()
        else
            @i += lower.length

        # {n, ...
        if @skipSpace() and @regex[@i] is ','
            @i++
            if @skipSpace() and @isEnd() then throw @unexpectedEnd()

            # {n, m}
            if (upper = @regex[@i...].match(NUMBER)?[0])
                @i += upper.length
                if @skipSpace() and @isEnd() then throw @unexpectedEnd()

                if @regex[@i] is '}'
                    @i++
                    return @parseAtomSuffix new Repeat atom, lower, true, upper
                else
                    throw @unmatchedError iLeft, '{'

            # {n, }
            else if @regex[@i] is '}'
                @i++
                return @parseAtomSuffix new Repeat atom, lower, true

            else
                throw @unmatchedError iLeft, '{'

        # {n}
        else if @regex[@i] is '}'
            @i++
            return @parseAtomSuffix new Repeat atom, lower, false
        else
            throw @unmatchedError iLeft, '{'

    parseTrailingContext: (atom) ->
        @i++
        unless @skipSpace() and not @isEnd()
            throw @unexpectedEnd()

        if (cond = @parseAtom()) and @skipSpace() and @isEnd()
            return new TailingContext atom, cond
        else
            throw @unexpectedCharacter()

    skipSpace: ->
        @i++ while @regex[@i] in [' ', '\n']

    isEnd: (i = @i) ->
        i > @regex.length - 1

    unexpectedCharacter: (i = @i) ->
        class UnexpectedCharacter extends Error
            constructor: (regex, i) ->
                @name = 'Unexpected character'
                @message = "error: unexpected character #{JSON.stringify regex[i]}\n#{regex}\n#{Array(i + 1).join(' ')}^\n"

        return new UnexpectedCharacter @regex, if i > @regex.length - 1 then @regex.length - 1 else i

    unmatchedError: (i, b = '(') ->
        class UnmatchedError extends Error
            constructor: (regex, i, match) ->
                @name = 'Unmatched error'
                @message = "error: unmatched '#{match}'\n#{regex}\n#{Array(i + 1).join(' ')}^\n"

        return new UnmatchedError @regex, i, b

    unexpectedEnd: ->
        class UnexpectedEndError extends Error
            constructor: (regex) ->
                @name = 'Unexpected end error'
                @message = "unexpected end of regular expression\n#{regex}\n#{Array(regex.length).join ' '}^\n"

        return new UnexpectedEndError @regex
