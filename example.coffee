re2j = require './re2j'
fs = require 'fs'

gen = new re2j()

gen.addDefine {
    HEX_PREFIX: '"0"[xX]'
    HEX_DIGITS: '[0-9a-fA-F]+'
    BIN_PREFIX: '"0"[bB]'
    BIN_DIGITS: '[01]+'

    INTEGER_SUFFIX_OPT: '(([uU]"ll")|([uU]"LL")|("ll"[uU]?)|("LL"[uU]?)|([uU][lL])|([lL][uU]?)|[uU])?'
}

gen.addAction {
    '("0"INTEGER_SUFFIX_OPT)|([1-9][0-9]*INTEGER_SUFFIX_OPT)':"DEC"
    '"0"[0-7]*INTEGER_SUFFIX_OPT': "OCT"
    'HEX_PREFIX HEX_DIGITS* INTEGER_SUFFIX_OPT': "HEX"
    'BIN_PREFIX BIN_DIGITS* INTEGER_SUFFIX_OPT': "BIN"
}

gen.generateMainDFA()
gen.generateDotData 're2j.dot', gen.mainDFA
fs.writeFileSync 'lexer.js', gen.generateCode gen.mainDFA
