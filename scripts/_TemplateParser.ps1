# ============================================================================
# Shared tokenizer + tolerant recursive block parser for Tekla Template Editor
# files (.tpl / .rpt). Dot-sourced by Render-TeklaTemplate.ps1 (preview),
# Get-TeklaGrammar.ps1 (allow-list harvest) and the -Strict validator so all
# three see an IDENTICAL parse tree — a name is only "unknown" to the validator
# if it was also absent when the allow-list was harvested.
#
# Parse tree node: [pscustomobject]@{ Keyword; Id; Line; Props(ordered); Children }
#   Props    = key -> value  (string / double / array-tuple / bare ident)
#   Children = nested blocks (same shape)
#
# TWO implementations live here and MUST stay behaviourally identical:
#   * the PowerShell functions below (Read-Tokens / Read-BlockBody / ...) are the
#     readable REFERENCE spec and the fallback;
#   * a compiled C# port at the bottom of this file is the FAST PATH that
#     Parse-Template actually dispatches to (~40x faster; the corpus is 128 MB,
#     and a per-character PowerShell loop costs ~12 min on it).
# Set $env:TEKLA_TPL_PARSER = 'ps' to force the reference path (A/B debugging).
# tests\Test-TeklaTemplateRoundTrip.ps1 is the regression gate for both.
# ============================================================================

function Read-Tokens {
    param([string]$Text)
    $toks = New-Object System.Collections.ArrayList
    $i = 0; $n = $Text.Length; $line = 1
    $add = { param($t, $v, $l) [void]$toks.Add([pscustomobject]@{ Type = $t; Value = $v; Line = $l }) }

    while ($i -lt $n) {
        $c = $Text[$i]
        if ($c -eq "`n") { $line++; $i++; continue }
        if ([char]::IsWhiteSpace($c)) { $i++; continue }

        # comments: // to end of line, /* ... */
        if ($c -eq '/' -and $i + 1 -lt $n -and $Text[$i + 1] -eq '/') {
            while ($i -lt $n -and $Text[$i] -ne "`n") { $i++ }; continue
        }
        if ($c -eq '/' -and $i + 1 -lt $n -and $Text[$i + 1] -eq '*') {
            $i += 2
            while ($i + 1 -lt $n -and -not ($Text[$i] -eq '*' -and $Text[$i + 1] -eq '/')) {
                if ($Text[$i] -eq "`n") { $line++ }; $i++
            }
            $i += 2; continue
        }

        # double-quoted string; \" and \\ are the only escapes that matter (formula quotes)
        if ($c -eq '"') {
            $sb = New-Object System.Text.StringBuilder
            $startLine = $line; $i++
            $closed = $false
            while ($i -lt $n) {
                $ch = $Text[$i]
                if ($ch -eq '\') {
                    if ($i + 1 -lt $n) {
                        $nx = $Text[$i + 1]
                        if ($nx -eq '"' -or $nx -eq '\') { [void]$sb.Append($nx); $i += 2; continue }
                    }
                    [void]$sb.Append($ch); $i++; continue
                }
                if ($ch -eq '"') { $i++; $closed = $true; break }
                if ($ch -eq "`n") { $line++ }
                [void]$sb.Append($ch); $i++
            }
            if (-not $closed) { throw "Parse error line ${startLine}: unterminated string." }
            & $add 'String' $sb.ToString() $startLine
            continue
        }

        # identifier / enum keyword (letters, digits, _ and . after first)
        if ($c -match '[A-Za-z_]') {
            $start = $i
            while ($i -lt $n -and $Text[$i] -match '[A-Za-z0-9_.]') { $i++ }
            & $add 'Ident' $Text.Substring($start, $i - $start) $line
            continue
        }

        # number (optionally signed, decimal, with scientific exponent e.g. 8.4e-05)
        if ($c -match '[0-9]' -or ($c -eq '-' -and $i + 1 -lt $n -and $Text[$i + 1] -match '[0-9.]')) {
            $start = $i
            if ($Text[$i] -eq '-') { $i++ }
            while ($i -lt $n -and $Text[$i] -match '[0-9.]') { $i++ }
            if ($i -lt $n -and ($Text[$i] -eq 'e' -or $Text[$i] -eq 'E')) {
                $j = $i + 1
                if ($j -lt $n -and ($Text[$j] -eq '+' -or $Text[$j] -eq '-')) { $j++ }
                if ($j -lt $n -and $Text[$j] -match '[0-9]') {
                    $i = $j
                    while ($i -lt $n -and $Text[$i] -match '[0-9]') { $i++ }
                }
            }
            & $add 'Number' $Text.Substring($start, $i - $start) $line
            continue
        }

        if ('{}()=;,'.Contains([string]$c)) { & $add 'Punct' ([string]$c) $line; $i++; continue }

        # unknown character: skip tolerantly (keeps old/varied shipped templates parseable)
        $i++
    }
    & $add 'EOF' '' $line
    return $toks
}

# Parser state is script-scoped for a simple recursive descent.
function New-Parser { param($Tokens) $script:PTok = $Tokens; $script:PPos = 0 }
function Peek-Tok  { $script:PTok[$script:PPos] }
function Next-Tok  { $t = $script:PTok[$script:PPos]; $script:PPos++; return $t }
function Expect-Punct {
    param([string]$P)
    $t = Next-Tok
    if (-not ($t.Type -eq 'Punct' -and $t.Value -eq $P)) {
        throw "Parse error line $($t.Line): expected '$P' but found '$($t.Value)'."
    }
    return $t
}

# Reads a value AND its source token kind: 'string' (was double-quoted), 'ident'
# (bare enum keyword like TRUE / LEFT), 'number', or — for a tuple — an array of the
# element kinds. The kind is what a canonical emitter needs to reproduce quoting
# exactly (the value alone can't distinguish `justify = LEFT` from `name = "LEFT"`).
# Returns @{ V = value; K = kind }.
function Read-ValueKinded {
    $t = Next-Tok
    switch ($t.Type) {
        'String' { return @{ V = $t.Value; K = 'string' } }
        'Number' { return @{ V = [double]::Parse($t.Value, [System.Globalization.CultureInfo]::InvariantCulture); K = 'number' } }
        'Ident'  { return @{ V = $t.Value; K = 'ident' } }
        'Punct'  {
            if ($t.Value -eq '(') {
                $arr = New-Object System.Collections.ArrayList
                $kinds = New-Object System.Collections.ArrayList
                if ((Peek-Tok).Type -eq 'Punct' -and (Peek-Tok).Value -eq ')') {
                    [void](Next-Tok)
                    return @{ V = @($arr.ToArray()); K = @($kinds.ToArray()) }
                }
                while ($true) {
                    $el = Read-ValueKinded
                    [void]$arr.Add($el.V)
                    [void]$kinds.Add($el.K)
                    $sep = Next-Tok
                    if ($sep.Type -eq 'Punct' -and $sep.Value -eq ')') { break }
                    if ($sep.Type -eq 'Punct' -and $sep.Value -eq ',') { continue }
                    throw "Parse error line $($sep.Line): expected ',' or ')' in tuple, found '$($sep.Value)'."
                }
                return @{ V = @($arr.ToArray()); K = @($kinds.ToArray()) }
            }
        }
    }
    throw "Parse error line $($t.Line): unexpected value token '$($t.Value)'."
}

function Read-Value {
    $kv = Read-ValueKinded
    if ($kv.V -is [array]) { return , $kv.V }
    return $kv.V
}

# Reads a block body given its keyword/id already consumed; expects '{' next.
function Read-BlockBody {
    param([string]$Keyword, $Id, [int]$Line)
    Expect-Punct '{' | Out-Null
    $node = [pscustomobject]@{
        Keyword   = $Keyword
        Id        = $Id
        Line      = $Line
        Props     = [ordered]@{}
        PropLines = [ordered]@{}   # key -> source line, for precise validator diagnostics
        PropKinds = [ordered]@{}   # key -> token kind ('string'|'ident'|'number'|kind[] for tuples), for the canonical emitter
        Children  = (New-Object System.Collections.ArrayList)
    }
    while ($true) {
        $p = Peek-Tok
        if ($p.Type -eq 'Punct' -and $p.Value -eq '}') { [void](Next-Tok); break }
        if ($p.Type -eq 'Punct' -and $p.Value -eq ';') { [void](Next-Tok); continue }  # tolerate stray ';'
        if ($p.Type -eq 'EOF') { throw "Parse error line $($p.Line): unexpected end of file (unbalanced '{' opened near line $Line)." }

        $head = Next-Tok
        if ($head.Type -ne 'Ident') {
            throw "Parse error line $($head.Line): expected a key or block keyword, found '$($head.Value)'."
        }
        $nx = Peek-Tok
        if ($nx.Type -eq 'Punct' -and $nx.Value -eq '=') {
            [void](Next-Tok)                 # '='
            $kv = Read-ValueKinded
            Expect-Punct ';' | Out-Null
            $node.Props[$head.Value] = $kv.V
            $node.PropLines[$head.Value] = $head.Line
            $node.PropKinds[$head.Value] = $kv.K
        }
        else {
            # nested block: optional id token (identifier or number), then '{ ... }'
            $cid = $null
            $pt = Peek-Tok
            if ($pt.Type -eq 'Ident' -or $pt.Type -eq 'Number') { $cid = (Next-Tok).Value }
            $child = Read-BlockBody -Keyword $head.Value -Id $cid -Line $head.Line
            [void]$node.Children.Add($child)
        }
    }
    # optional trailing ';' after a nested block's closing brace
    $after = Peek-Tok
    if ($after.Type -eq 'Punct' -and $after.Value -eq ';') { [void](Next-Tok) }
    return $node
}

# Reference implementation. Parse-Template (bottom of file) dispatches here only
# when the compiled fast path is unavailable or disabled.
function Parse-TemplateReference {
    param([string]$Text)
    New-Parser (Read-Tokens $Text)
    $head = Next-Tok
    if ($head.Type -ne 'Ident') { throw "Parse error line $($head.Line): expected 'template', found '$($head.Value)'." }
    $id = $null
    $pt = Peek-Tok
    if ($pt.Type -eq 'Ident' -or $pt.Type -eq 'Number') { $id = (Next-Tok).Value }
    return Read-BlockBody -Keyword $head.Value -Id $id -Line $head.Line
}

# --- property accessors ------------------------------------------------------
function Get-Prop  { param($Node, [string]$Name) if ($Node.Props.Contains($Name)) { $Node.Props[$Name] } else { $null } }
function Get-Num   { param($Node, [string]$Name, $Default) $v = Get-Prop $Node $Name; if ($null -eq $v) { $Default } else { [double]$v } }
function Get-Str   { param($Node, [string]$Name, $Default) $v = Get-Prop $Node $Name; if ($null -eq $v) { $Default } else { [string]$v } }
function Get-Tuple { param($Node, [string]$Name, $Default) $v = Get-Prop $Node $Name; if ($null -eq $v) { return $Default }; if ($v -is [array]) { return $v } else { return @($v) } }

function Get-ChildBlocks { param($Node, [string[]]$Keywords) $Node.Children | Where-Object { $Keywords -contains $_.Keyword } }

# Walk every block in the tree (depth-first, includes the root).
function Get-AllBlocks {
    param($Node)
    $Node
    foreach ($c in $Node.Children) { Get-AllBlocks $c }
}

# ============================================================================
# Fast path — compiled C# port of Read-Tokens + the recursive descent above.
#
# Why: the lexer is a per-character loop, and classifying characters with the
# PowerShell -match operator runs the .NET regex engine (and repopulates
# $Matches) tens of millions of times. Measured on the shipped 2026.0 corpus
# (2,688 files / 134M chars): reference path 185k chars/s (~12 min), compiled
# path 8.0M chars/s (17 s).
#
# The port mirrors the reference EXACTLY, including tolerance rules (unknown
# characters skipped, stray ';' allowed) and error message text. Two details
# that are easy to get wrong if this is ever re-derived:
#   * identifier/number character classes are ASCII-only, because the reference
#     used -match '[A-Za-z_]' — char.IsLetter would wrongly accept 'a', 'ä'…;
#   * Props/PropLines/PropKinds use a case-INSENSITIVE comparer, because that is
#     what PowerShell's [ordered]@{} does.
# Verified: all 2,688 shipped templates produce tree-identical results and the
# identical 2,685-parsed / 3-failed split.
# ============================================================================

$script:TplParserCS = @'
using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.Specialized;
using System.Globalization;
using System.Text;

namespace TeklaTpl {

    public class Node {
        public string Keyword;
        public object Id;
        public int Line;
        public OrderedDictionary Props;
        public OrderedDictionary PropLines;
        public OrderedDictionary PropKinds;
        public ArrayList Children;

        public Node(string kw, object id, int line, IEqualityComparer cmp) {
            Keyword   = kw;
            Id        = id;
            Line      = line;
            Props     = new OrderedDictionary(cmp);
            PropLines = new OrderedDictionary(cmp);
            PropKinds = new OrderedDictionary(cmp);
            Children  = new ArrayList();
        }
    }

    internal struct Tok {
        public int Type;      // 0 String, 1 Number, 2 Ident, 3 Punct, 4 EOF
        public string Value;
        public int Line;
        public Tok(int t, string v, int l) { Type = t; Value = v; Line = l; }
    }

    public static class TemplateParser {

        const int T_STRING = 0, T_NUMBER = 1, T_IDENT = 2, T_PUNCT = 3, T_EOF = 4;

        // Matches PowerShell's [ordered]@{} key comparison.
        static readonly IEqualityComparer KeyCmp = StringComparer.CurrentCultureIgnoreCase;

        static bool IsIdentStart(char c) {
            return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c == '_';
        }
        static bool IsIdentPart(char c) {
            return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_' || c == '.';
        }
        static bool IsDigit(char c) { return c >= '0' && c <= '9'; }

        static List<Tok> Lex(string text) {
            var toks = new List<Tok>(text.Length / 6 + 16);
            int i = 0, n = text.Length, line = 1;

            while (i < n) {
                char c = text[i];
                if (c == '\n') { line++; i++; continue; }
                if (char.IsWhiteSpace(c)) { i++; continue; }

                if (c == '/' && i + 1 < n && text[i + 1] == '/') {
                    while (i < n && text[i] != '\n') i++;
                    continue;
                }
                if (c == '/' && i + 1 < n && text[i + 1] == '*') {
                    i += 2;
                    while (i + 1 < n && !(text[i] == '*' && text[i + 1] == '/')) {
                        if (text[i] == '\n') line++;
                        i++;
                    }
                    i += 2;
                    continue;
                }

                if (c == '"') {
                    var sb = new StringBuilder();
                    int startLine = line;
                    i++;
                    bool closed = false;
                    while (i < n) {
                        char ch = text[i];
                        if (ch == '\\') {
                            if (i + 1 < n) {
                                char nx = text[i + 1];
                                if (nx == '"' || nx == '\\') { sb.Append(nx); i += 2; continue; }
                            }
                            sb.Append(ch); i++; continue;
                        }
                        if (ch == '"') { i++; closed = true; break; }
                        if (ch == '\n') line++;
                        sb.Append(ch); i++;
                    }
                    if (!closed) throw new Exception("Parse error line " + startLine + ": unterminated string.");
                    toks.Add(new Tok(T_STRING, sb.ToString(), startLine));
                    continue;
                }

                if (IsIdentStart(c)) {
                    int start = i;
                    while (i < n && IsIdentPart(text[i])) i++;
                    toks.Add(new Tok(T_IDENT, text.Substring(start, i - start), line));
                    continue;
                }

                if (IsDigit(c) || (c == '-' && i + 1 < n && (IsDigit(text[i + 1]) || text[i + 1] == '.'))) {
                    int start = i;
                    if (text[i] == '-') i++;
                    while (i < n && (IsDigit(text[i]) || text[i] == '.')) i++;
                    if (i < n && (text[i] == 'e' || text[i] == 'E')) {
                        int j = i + 1;
                        if (j < n && (text[j] == '+' || text[j] == '-')) j++;
                        if (j < n && IsDigit(text[j])) {
                            i = j;
                            while (i < n && IsDigit(text[i])) i++;
                        }
                    }
                    toks.Add(new Tok(T_NUMBER, text.Substring(start, i - start), line));
                    continue;
                }

                if (c == '{' || c == '}' || c == '(' || c == ')' || c == '=' || c == ';' || c == ',') {
                    toks.Add(new Tok(T_PUNCT, c.ToString(), line));
                    i++;
                    continue;
                }

                i++;   // unknown character: skip tolerantly
            }
            toks.Add(new Tok(T_EOF, "", line));
            return toks;
        }

        class State {
            public List<Tok> Toks;
            public int Pos;
            public Tok Peek() { return Toks[Pos]; }
            public Tok Next() { return Toks[Pos++]; }
        }

        static Tok ExpectPunct(State s, string p) {
            Tok t = s.Next();
            if (!(t.Type == T_PUNCT && t.Value == p))
                throw new Exception("Parse error line " + t.Line + ": expected '" + p + "' but found '" + t.Value + "'.");
            return t;
        }

        // returns [0] = value, [1] = source token kind
        static object[] ReadValueKinded(State s) {
            Tok t = s.Next();
            if (t.Type == T_STRING) return new object[] { t.Value, "string" };
            if (t.Type == T_NUMBER) return new object[] { double.Parse(t.Value, CultureInfo.InvariantCulture), "number" };
            if (t.Type == T_IDENT)  return new object[] { t.Value, "ident" };
            if (t.Type == T_PUNCT && t.Value == "(") {
                var vals  = new ArrayList();
                var kinds = new ArrayList();
                Tok p = s.Peek();
                if (p.Type == T_PUNCT && p.Value == ")") {
                    s.Next();
                    return new object[] { vals.ToArray(), kinds.ToArray() };
                }
                while (true) {
                    object[] el = ReadValueKinded(s);
                    vals.Add(el[0]);
                    kinds.Add(el[1]);
                    Tok sep = s.Next();
                    if (sep.Type == T_PUNCT && sep.Value == ")") break;
                    if (sep.Type == T_PUNCT && sep.Value == ",") continue;
                    throw new Exception("Parse error line " + sep.Line + ": expected ',' or ')' in tuple, found '" + sep.Value + "'.");
                }
                return new object[] { vals.ToArray(), kinds.ToArray() };
            }
            throw new Exception("Parse error line " + t.Line + ": unexpected value token '" + t.Value + "'.");
        }

        static Node ReadBlockBody(State s, string keyword, object id, int line) {
            ExpectPunct(s, "{");
            var node = new Node(keyword, id, line, KeyCmp);

            while (true) {
                Tok p = s.Peek();
                if (p.Type == T_PUNCT && p.Value == "}") { s.Next(); break; }
                if (p.Type == T_PUNCT && p.Value == ";") { s.Next(); continue; }
                if (p.Type == T_EOF)
                    throw new Exception("Parse error line " + p.Line + ": unexpected end of file (unbalanced '{' opened near line " + line + ").");

                Tok head = s.Next();
                if (head.Type != T_IDENT)
                    throw new Exception("Parse error line " + head.Line + ": expected a key or block keyword, found '" + head.Value + "'.");

                Tok nx = s.Peek();
                if (nx.Type == T_PUNCT && nx.Value == "=") {
                    s.Next();
                    object[] kv = ReadValueKinded(s);
                    ExpectPunct(s, ";");
                    node.Props[head.Value]     = kv[0];
                    node.PropLines[head.Value] = head.Line;
                    node.PropKinds[head.Value] = kv[1];
                }
                else {
                    object cid = null;
                    Tok pt = s.Peek();
                    if (pt.Type == T_IDENT || pt.Type == T_NUMBER) cid = s.Next().Value;
                    node.Children.Add(ReadBlockBody(s, head.Value, cid, head.Line));
                }
            }

            Tok after = s.Peek();
            if (after.Type == T_PUNCT && after.Value == ";") s.Next();
            return node;
        }

        public static Node Parse(string text) {
            var s = new State();
            s.Toks = Lex(text);
            s.Pos = 0;

            Tok head = s.Next();
            if (head.Type != T_IDENT)
                throw new Exception("Parse error line " + head.Line + ": expected 'template', found '" + head.Value + "'.");
            object id = null;
            Tok pt = s.Peek();
            if (pt.Type == T_IDENT || pt.Type == T_NUMBER) id = s.Next().Value;
            return ReadBlockBody(s, head.Value, id, head.Line);
        }
    }
}
'@

# Compiling the C# above costs ~0.5 s, which would dominate a single-file render,
# so the assembly is cached in the temp dir under a name derived from a hash of
# the source: editing the C# above automatically produces a different file name,
# so a stale cache is impossible and no cleanup step is needed. Cached load ~50 ms.
$script:TplFastParser = $null

function Initialize-TplFastParser {
    if ($null -ne $script:TplFastParser) { return $script:TplFastParser }

    if ($env:TEKLA_TPL_PARSER -eq 'ps') { $script:TplFastParser = $false; return $false }
    if ('TeklaTpl.TemplateParser' -as [type]) { $script:TplFastParser = $true; return $true }

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try   { $hash = ($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($script:TplParserCS)) | ForEach-Object { $_.ToString('x2') }) -join '' }
    finally { $sha.Dispose() }
    $dll = Join-Path ([System.IO.Path]::GetTempPath()) ("TeklaTplParser-" + $hash.Substring(0, 16) + ".dll")

    # 1) cached assembly  2) compile + cache  3) in-memory compile  4) reference path
    try {
        if (Test-Path -LiteralPath $dll) { Add-Type -Path $dll -ErrorAction Stop }
        else {
            $tmp = "$dll.$PID.tmp"
            Add-Type -Language CSharp -TypeDefinition $script:TplParserCS -OutputAssembly $tmp -ErrorAction Stop
            try { Move-Item -LiteralPath $tmp -Destination $dll -ErrorAction Stop }
            catch { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }   # another process won the race
            Add-Type -Path ((Test-Path -LiteralPath $dll) ? $dll : $tmp) -ErrorAction Stop
        }
        $script:TplFastParser = $true
    }
    catch {
        try {
            Add-Type -Language CSharp -TypeDefinition $script:TplParserCS -ErrorAction Stop
            $script:TplFastParser = $true
        }
        catch {
            Write-Verbose "Compiled parser unavailable ($($_.Exception.Message)); using the PowerShell reference parser."
            $script:TplFastParser = $false
        }
    }
    return $script:TplFastParser
}

function Parse-Template {
    param([string]$Text)
    if (Initialize-TplFastParser) {
        # Unwrap MethodInvocationException so a parse error surfaces as the bare
        # "Parse error line N: ..." text the reference path throws — callers print
        # $_.Exception.Message straight to the user.
        try { return [TeklaTpl.TemplateParser]::Parse($Text) }
        catch [System.Management.Automation.MethodInvocationException] {
            throw $_.Exception.InnerException.Message
        }
    }
    return Parse-TemplateReference -Text $Text
}
