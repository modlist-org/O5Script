using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;

namespace O5Script.Syntax;

public sealed class Lexer {
    private readonly string _src;
    private readonly int _len;
    private int _pos;

    public Lexer(string source) {
        _src = source ?? string.Empty;
        _len = _src.Length;
        _pos = 0;
    }

    public List<Token> Tokenize() {
        var tokens = new List<Token>();
        while (_pos < _len) {
            SkipWhitespaceAndComments();
            if (_pos >= _len) break;

            int start = _pos;
            char c = _src[_pos];

            if (c == '#') {
                _pos++;
                int idStart = _pos;
                while (_pos < _len && (char.IsLetterOrDigit(_src[_pos]) || _src[_pos] == '_')) {
                    _pos++;
                }
                string tagName = _src[idStart.._pos];
                tokens.Add(new Token(TokenType.HostTag, tagName, start, _pos - start));
                continue;
            }

            if (c == '"') {
                TokenizeString(tokens);
                continue;
            }

            if (char.IsDigit(c) || (c == '.' && _pos + 1 < _len && char.IsDigit(_src[_pos + 1]))) {
                tokens.Add(ScanNumber());
                continue;
            }

            if (char.IsLetter(c) || c == '_') {
                tokens.Add(ScanIdentifier());
                continue;
            }

            _pos++;
            switch (c) {
                case '+':
                    if (Match('=')) tokens.Add(new Token(TokenType.PlusEqual, "+=", start, 2));
                    else tokens.Add(new Token(TokenType.Plus, "+", start, 1));
                    break;
                case '-':
                    if (Match('=')) tokens.Add(new Token(TokenType.MinusEqual, "-=", start, 2));
                    else tokens.Add(new Token(TokenType.Minus, "-", start, 1));
                    break;
                case '*':
                    if (Match('=')) tokens.Add(new Token(TokenType.StarEqual, "*=", start, 2));
                    else tokens.Add(new Token(TokenType.Star, "*", start, 1));
                    break;
                case '/':
                    if (Match('=')) tokens.Add(new Token(TokenType.SlashEqual, "/=", start, 2));
                    else tokens.Add(new Token(TokenType.Slash, "/", start, 1));
                    break;
                case '%':
                    tokens.Add(new Token(TokenType.Percent, "%", start, 1));
                    break;
                case '&':
                    if (Match('&')) tokens.Add(new Token(TokenType.AndAnd, "&&", start, 2));
                    else tokens.Add(new Token(TokenType.Amp, "&", start, 1));
                    break;
                case '|':
                    if (Match('|')) tokens.Add(new Token(TokenType.OrOr, "||", start, 2));
                    else tokens.Add(new Token(TokenType.Pipe, "|", start, 1));
                    break;
                case '^':
                    tokens.Add(new Token(TokenType.Caret, "^", start, 1));
                    break;
                case '~':
                    tokens.Add(new Token(TokenType.Tilde, "~", start, 1));
                    break;
                case '!':
                    if (Match('=')) tokens.Add(new Token(TokenType.BangEqual, "!=", start, 2));
                    else tokens.Add(new Token(TokenType.Bang, "!", start, 1));
                    break;
                case '=':
                    if (Match('=')) tokens.Add(new Token(TokenType.EqualEqual, "==", start, 2));
                    else if (Match('>')) tokens.Add(new Token(TokenType.Arrow, "=>", start, 2));
                    else tokens.Add(new Token(TokenType.Equal, "=", start, 1));
                    break;
                case '<':
                    if (Match('<')) tokens.Add(new Token(TokenType.LessLess, "<<", start, 2));
                    else if (Match('=')) tokens.Add(new Token(TokenType.LessEqual, "<=", start, 2));
                    else tokens.Add(new Token(TokenType.Less, "<", start, 1));
                    break;
                case '>':
                    if (Match('>')) tokens.Add(new Token(TokenType.GreaterGreater, ">>", start, 2));
                    else if (Match('=')) tokens.Add(new Token(TokenType.GreaterEqual, ">=", start, 2));
                    else tokens.Add(new Token(TokenType.Greater, ">", start, 1));
                    break;
                case '.':
                    if (Match('.')) tokens.Add(new Token(TokenType.DotDot, "..", start, 2));
                    else tokens.Add(new Token(TokenType.Dot, ".", start, 1));
                    break;
                case '@':
                    tokens.Add(new Token(TokenType.At, "@", start, 1));
                    break;
                case '?':
                    tokens.Add(new Token(TokenType.Question, "?", start, 1));
                    break;
                case ':':
                    tokens.Add(new Token(TokenType.Colon, ":", start, 1));
                    break;
                case '(':
                    tokens.Add(new Token(TokenType.LParen, "(", start, 1));
                    break;
                case ')':
                    tokens.Add(new Token(TokenType.RParen, ")", start, 1));
                    break;
                case '{':
                    tokens.Add(new Token(TokenType.LBrace, "{", start, 1));
                    break;
                case '}':
                    tokens.Add(new Token(TokenType.RBrace, "}", start, 1));
                    break;
                case '[':
                    tokens.Add(new Token(TokenType.LBracket, "[", start, 1));
                    break;
                case ']':
                    tokens.Add(new Token(TokenType.RBracket, "]", start, 1));
                    break;
                case ',':
                    tokens.Add(new Token(TokenType.Comma, ",", start, 1));
                    break;
                case ';':
                    tokens.Add(new Token(TokenType.Semicolon, ";", start, 1));
                    break;
                default:
                    break;
            }
        }

        tokens.Add(new Token(TokenType.Eof, string.Empty, _pos, 0));
        return tokens;
    }

    private void TokenizeString(List<Token> tokens) {
        int strStart = _pos++;
        var sb = new StringBuilder();
        bool hasInterpolation = false;

        while (_pos < _len) {
            char c = _src[_pos];
            if (c == '"') {
                _pos++;
                break;
            }

            if (c == '{' && _pos + 1 < _len && _src[_pos + 1] == '{') {
                sb.Append('{');
                _pos += 2;
                continue;
            }
            if (c == '}' && _pos + 1 < _len && _src[_pos + 1] == '}') {
                sb.Append('}');
                _pos += 2;
                continue;
            }

            if (c == '{') {
                hasInterpolation = true;
                if (sb.Length > 0 || tokens.Count == 0 || tokens[^1].Type != TokenType.Plus) {
                    tokens.Add(new Token(TokenType.String, sb.ToString(), strStart, _pos - strStart));
                    tokens.Add(new Token(TokenType.Plus, "+", _pos, 1));
                    sb.Clear();
                }

                _pos++;
                tokens.Add(new Token(TokenType.LParen, "(", _pos - 1, 1));

                int braceDepth = 1;
                int innerStart = _pos;
                while (_pos < _len && braceDepth > 0) {
                    if (_src[_pos] == '{') braceDepth++;
                    else if (_src[_pos] == '}') {
                        braceDepth--;
                        if (braceDepth == 0) break;
                    }
                    _pos++;
                }

                string innerSrc = _src[innerStart.._pos];
                if (_pos < _len && _src[_pos] == '}') _pos++;

                var innerLexer = new Lexer(innerSrc);
                var innerTokens = innerLexer.Tokenize();
                for (int i = 0; i < innerTokens.Count - 1; i++) {
                    tokens.Add(innerTokens[i]);
                }

                tokens.Add(new Token(TokenType.RParen, ")", _pos - 1, 1));
                tokens.Add(new Token(TokenType.Plus, "+", _pos, 1));
                strStart = _pos;
                continue;
            }

            if (c == '\\' && _pos + 1 < _len) {
                _pos++;
                char esc = _src[_pos++];
                sb.Append(esc switch {
                    'n' => '\n',
                    'r' => '\r',
                    't' => '\t',
                    '\\' => '\\',
                    '"' => '"',
                    _ => esc
                });
                continue;
            }

            sb.Append(c);
            _pos++;
        }

        if (!hasInterpolation || sb.Length > 0) {
            tokens.Add(new Token(TokenType.String, sb.ToString(), strStart, _pos - strStart));
        } else if (hasInterpolation && tokens.Count > 0 && tokens[^1].Type == TokenType.Plus) {
            tokens.Add(new Token(TokenType.String, string.Empty, _pos, 0));
        }
    }

    private Token ScanNumber() {
        int start = _pos;
        while (_pos < _len && char.IsDigit(_src[_pos])) _pos++;

        if (_pos < _len && _src[_pos] == '.' && _pos + 1 < _len && char.IsDigit(_src[_pos + 1])) {
            _pos++;
            while (_pos < _len && char.IsDigit(_src[_pos])) _pos++;
        }

        string text = _src[start.._pos];
        double val = double.Parse(text, CultureInfo.InvariantCulture);
        return new Token(TokenType.Number, text, start, _pos - start, val);
    }

    private Token ScanIdentifier() {
        int start = _pos;
        while (_pos < _len && (char.IsLetterOrDigit(_src[_pos]) || _src[_pos] == '_')) {
            _pos++;
        }

        string text = _src[start.._pos];
        TokenType type = text switch {
            "let" => TokenType.Let,
            "sta" => TokenType.Sta,
            "con" => TokenType.Con,
            "if" => TokenType.If,
            "lf" => TokenType.Lf,
            "el" => TokenType.El,
            "lop" => TokenType.Lop,
            "out" => TokenType.Out,
            "skp" => TokenType.Skp,
            "fun" => TokenType.Fun,
            "ret" => TokenType.Ret,
            "tag" => TokenType.Tag,
            "num" => TokenType.TypeNum,
            "str" => TokenType.TypeStr,
            "tru" => TokenType.Number,
            "fls" => TokenType.Number,
            _ => TokenType.Identifier
        };

        double numVal = text == "tru" ? 1.0 : (text == "fls" ? 0.0 : 0.0);
        return new Token(type, text, start, _pos - start, numVal);
    }

    private void SkipWhitespaceAndComments() {
        while (_pos < _len) {
            char c = _src[_pos];
            if (char.IsWhiteSpace(c)) {
                _pos++;
                continue;
            }

            if (c == '/' && _pos + 1 < _len && _src[_pos + 1] == '/') {
                _pos += 2;
                while (_pos < _len && _src[_pos] != '\n') _pos++;
                continue;
            }

            if (c == '/' && _pos + 1 < _len && _src[_pos + 1] == '*') {
                _pos += 2;
                while (_pos + 1 < _len && !(_src[_pos] == '*' && _src[_pos + 1] == '/')) {
                    _pos++;
                }
                if (_pos + 1 < _len) _pos += 2;
                continue;
            }

            break;
        }
    }

    private bool Match(char expected) {
        if (_pos < _len && _src[_pos] == expected) {
            _pos++;
            return true;
        }
        return false;
    }
}
