_ = require 'lodash'
jsesc = require 'jsesc'

module.exports = (entrance) ->
    yych = "yystr[yycursor]"
    preDefine = """
                    var yytype = null,
                        yytokstart = 0,
                        yycursor = 0,
                        yystr,
                        #{if @newlineStr.length > 1 then "yynewline_track = 0, yynewline_str = #{jsesc @newlineStr}" else ""}
                        yytoken = function() {this.type = yytype;this.value = yystr.slice(yytokstart, yycursor - yytokstart + 1);yytokstart = yycursor};
                    """

    fnBody = ""
    entrance.visitAll (v) =>
        jumpTable = {}
        fnBody += "function yy#{v.id} () {\n"

        if _.isNumber v.actionId then fnBody += "yytype = '#{@action[v.actionId].name}';\n"

        for e in v.edges
            (jumpTable[e.dest.id] ?= []).push {
                lower: "'#{jsesc(e.lower)}'"
                upper: "'#{jsesc(e.upper)}'"
                jumpTo: e.dest.id
            }

        ifGroup = []
        for own jumpId, ranges of jumpTable
            cond = []

            for r in ranges
                if r.lower is r.upper
                    cond.push "#{yych} == #{r.lower}"
                else
                    cond.push "#{r.lower} <= #{yych} && #{yych} <= #{r.upper}"

            ifGroup.push """
                         if (#{cond.join ' || '}) {
                            yycursor++;
                            return yy#{jumpId}();
                         }
                         """

        if v.isAcceptedState
            ifGroup.push "{return new yytoken();}"
        else
            ifGroup.push "{throw new Error(\'Unexpected charcter\')}"

        fnBody += ifGroup.join(' else ') + '}\n'

    return """
           (function (){#{preDefine}#{fnBody}return function (s){yystr = s;return yy0();}})()
           """
