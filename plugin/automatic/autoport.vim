" -----------------------------------------------------------------------------
" AUTOPORT for HonkW93/automatic-verilog
" File: plugin/automatic/autoport.vim
" Purpose:
"   Generate the parent module's ports from a named child module while leaving
"   all text before /*AUTOPORT(module)*/ untouched.
"
" Supported marker:
"   /*AUTOPORT(a)*/
"
" Commands:
"   :AutoPort        Update the next AUTOPORT marker from the cursor
"   :AutoPortAll     Update all AUTOPORT markers in the current buffer
"   :KillAutoPort    Remove the expansion after the next AUTOPORT marker
"   :KillAutoPortAll Remove expansions after all AUTOPORT markers
"
" Notes:
"   - Does not modify AUTOINST implementation or generated instance wiring.
"   - Copies source port lines in source order, retaining `ifdef/`else/`endif.
"   - Uses one ANSI port declaration per source line (the usual RTL style).
"   - For name-mismatch filtering, expand AUTOINST first so explicit .port(signal)
"     connections are visible to this script.
"   - Conflicting names are filtered from the generated region.
" -----------------------------------------------------------------------------

if exists('g:loaded_automatic_verilog_autoport')
    finish
endif
let g:loaded_automatic_verilog_autoport = 1

command! -bar AutoPort        call g:AutoPort(0)
command! -bar AutoPortAll     call g:AutoPort(1)
command! -bar KillAutoPort    call g:KillAutoPort(0)
command! -bar KillAutoPortAll call g:KillAutoPort(1)

if has('menu')
    " Avoid duplicate entries when the script is sourced again.
    silent! aunmenu &Verilog.AutoPort
    amenu 9998.2.1 &Verilog.&AutoPort.AutoPort(0)\ \ \ \ \ \ \ \ \ \ \ One :call g:AutoPort(0)<CR>
    amenu 9998.2.2 &Verilog.&AutoPort.AutoPort(1)\ \ \ \ \ \ \ \ \ \ \ \ All :call g:AutoPort(1)<CR>
    amenu 9998.2.3 &Verilog.&AutoPort.KillAutoPort(0)\ \ \ \ \ \ One :call g:KillAutoPort(0)<CR>
    amenu 9998.2.4 &Verilog.&AutoPort.KillAutoPort(1)\ \ \ \ \ \ \ \ All :call g:KillAutoPort(1)<CR>
endif

let s:autop_marker_pat = '/\*AUTOPORT\s*(\s*\h\w*\s*)\s*\*/'

function! g:AutoPort(mode) abort
    if a:mode != 0 && a:mode != 1
        echohl ErrorMsg | echomsg 'AutoPort: mode must be 0 or 1' | echohl None
        return
    endif

    let l:save_pos = getpos('.')
    let l:save_view = winsaveview()
    let l:markers = []

    if a:mode == 0
        if search(s:autop_marker_pat, 'W') > 0
            let l:lnum = line('.')
            if getline(l:lnum) !~ '^\s*//'
                call s:AutoPortAt(l:lnum)
                call winrestview(l:save_view)
                call setpos('.', l:save_pos)
                echomsg 'AutoPort: updated one marker'
                return
            endif
        endif
        call winrestview(l:save_view)
        call setpos('.', l:save_pos)
        echomsg 'AutoPort: no AUTOPORT(module) marker found after cursor'
        return
    endif

    " Snapshot marker lines first and process bottom-up, so line edits do not
    " invalidate positions and the same marker cannot be processed repeatedly.
    call cursor(1, 1)
    while search(s:autop_marker_pat, 'W') > 0
        if getline('.') !~ '^\s*//'
            call add(l:markers, line('.'))
        endif
        call cursor(line('.') + 1, 1)
    endwhile
    for l:lnum in reverse(l:markers)
        call s:AutoPortAt(l:lnum)
    endfor

    call winrestview(l:save_view)
    call setpos('.', l:save_pos)
    if empty(l:markers)
        echomsg 'AutoPort: no AUTOPORT(module) markers found'
    else
        echomsg 'AutoPort: updated ' . len(l:markers) . ' marker(s)'
    endif
endfunction


function! g:KillAutoPort(mode) abort
    if a:mode != 0 && a:mode != 1
        echohl ErrorMsg | echomsg 'KillAutoPort: mode must be 0 or 1' | echohl None
        return
    endif

    let l:save_pos = getpos('.')
    let l:save_view = winsaveview()
    let l:markers = []

    if a:mode == 0
        if search(s:autop_marker_pat, 'W') > 0
            let l:lnum = line('.')
            if getline(l:lnum) !~ '^\s*//'
                call s:KillAutoPortAt(l:lnum)
                call winrestview(l:save_view)
                call setpos('.', l:save_pos)
                echomsg 'KillAutoPort: removed one AUTOPORT expansion'
                return
            endif
        endif
        call winrestview(l:save_view)
        call setpos('.', l:save_pos)
        echomsg 'KillAutoPort: no AUTOPORT(module) marker found after cursor'
        return
    endif

    " Snapshot marker lines first and process bottom-up, so line deletions do
    " not invalidate the positions of markers above them.
    call cursor(1, 1)
    while search(s:autop_marker_pat, 'W') > 0
        if getline('.') !~ '^\s*//'
            call add(l:markers, line('.'))
        endif
        call cursor(line('.') + 1, 1)
    endwhile
    for l:lnum in reverse(l:markers)
        call s:KillAutoPortAt(l:lnum)
    endfor

    call winrestview(l:save_view)
    call setpos('.', l:save_pos)
    if empty(l:markers)
        echomsg 'KillAutoPort: no AUTOPORT(module) markers found'
    else
        echomsg 'KillAutoPort: removed ' . len(l:markers) . ' AUTOPORT expansion(s)'
    endif
endfunction

function! s:KillAutoPortAt(marker_line) abort
    let l:marker_text = getline(a:marker_line)
    let l:marker_start = match(l:marker_text, s:autop_marker_pat)
    if l:marker_start < 0
        return
    endif
    let l:marker = matchstr(l:marker_text, s:autop_marker_pat)
    let l:marker_end = l:marker_start + strlen(l:marker)

    " The expansion occupies the region after the marker and before the
    " module header's closing );. Keep the marker and closing token intact.
    let l:close = s:FindCurrentHeaderClose(a:marker_line, l:marker_end)
    if empty(l:close)
        echohl ErrorMsg | echomsg 'KillAutoPort: cannot find closing ); for marker at line ' . a:marker_line | echohl None
        return
    endif

    let l:close_line = l:close[0]
    let l:close_col = l:close[1]
    let l:prefix = strpart(l:marker_text, 0, l:marker_end)
    let l:close_text = getline(l:close_line)
    let l:suffix = strpart(l:close_text, l:close_col)

    if l:close_line == a:marker_line
        " Marker and closing token share one line.
        call setline(a:marker_line, l:prefix . l:suffix)
        return
    endif

    " Preserve the closing line's indentation and everything from `);` onward.
    let l:close_replacement = matchstr(l:close_text, '^\s*') . l:suffix
    call setline(a:marker_line, l:prefix)

    " Remove all lines between the marker and closing token, then place the
    " preserved closing token directly below the marker.
    if l:close_line > a:marker_line + 1
        execute (a:marker_line + 1) . ',' . (l:close_line - 1) . 'delete _'
    endif
    call setline(a:marker_line + 1, l:close_replacement)
endfunction


function! s:AutoPortAt(marker_line) abort
    let l:marker_text = getline(a:marker_line)
    let l:marker_start = match(l:marker_text, s:autop_marker_pat)
    if l:marker_start < 0
        return
    endif
    let l:marker = matchstr(l:marker_text, s:autop_marker_pat)
    let l:module = matchstr(l:marker, '(\s*\zs\h\w*\ze\s*)')
    if empty(l:module)
        echohl ErrorMsg | echomsg 'AutoPort: invalid marker at line ' . a:marker_line | echohl None
        return
    endif
    let l:marker_end = l:marker_start + strlen(l:marker)

    let l:source_file = s:FindModuleFile(l:module)
    if empty(l:source_file) || !filereadable(l:source_file)
        echohl ErrorMsg | echomsg 'AutoPort: cannot find source for module ' . l:module | echohl None
        return
    endif
    let l:src_lines = readfile(l:source_file)
    let l:src_body = s:GetModulePortBody(l:src_lines, l:module)
    if empty(l:src_body)
        echohl ErrorMsg | echomsg 'AutoPort: cannot parse ANSI port list for module ' . l:module . ' in ' . l:source_file | echohl None
        return
    endif

    let l:close = s:FindCurrentHeaderClose(a:marker_line, l:marker_end)
    if empty(l:close)
        echohl ErrorMsg | echomsg 'AutoPort: cannot find closing ); for marker at line ' . a:marker_line | echohl None
        return
    endif
    let l:close_line = l:close[0]
    let l:close_col = l:close[1]

    " Record ports from the previous AUTOPORT expansion. Like AUTOINST, an
    " empty old port list is treated as an initial expansion: it does not mark
    " every current port as PORT_NEW.
    let l:old_port_names = []
    let l:old_port_name_set = {}
    if l:close_line > a:marker_line + 1
        for l:i in range(a:marker_line + 1, l:close_line - 1)
            let l:old_name = s:PortNameFromLine(getline(l:i))
            if !empty(l:old_name) && !has_key(l:old_port_name_set, l:old_name)
                call add(l:old_port_names, l:old_name)
                let l:old_port_name_set[l:old_name] = 1
            endif
        endfor
    endif

    " Get all port names declared by the current child module. This set is
    " deliberately collected before parent-side conflict filtering, so a port
    " filtered by a parent declaration is not falsely reported as PORT_DEL.
    let l:clean_src = s:StripComments(l:src_body)
    let l:source_port_name_set = {}
    for l:i in range(0, len(l:clean_src) - 1)
        let l:source_name = s:PortNameFromLine(l:clean_src[l:i])
        if !empty(l:source_name)
            let l:source_port_name_set[l:source_name] = 1
        endif
    endfor

    " Conflict set = manually declared ports before the marker + declarations in
    " this module body. The old AUTOPORT region is intentionally excluded.
    let l:conflicts = {}
    " Find the enclosing module declaration first. Do not treat ports from a
    " previous module in the same file as conflicts.
    let l:mod_start = a:marker_line
    while l:mod_start > 1 && getline(l:mod_start) !~ '^\s*module\>'
        let l:mod_start -= 1
    endwhile
    let l:header_before = []
    if l:mod_start <= a:marker_line
        if l:mod_start < a:marker_line
            let l:header_before = getline(l:mod_start, a:marker_line - 1)
        endif
        call add(l:header_before, strpart(l:marker_text, 0, l:marker_start))
    endif
    for l:line in l:header_before
        let l:pname = s:PortNameFromLine(l:line)
        if !empty(l:pname)
            let l:conflicts[l:pname] = 1
        endif
    endfor

    let l:body_start = l:close_line + 1
    let l:body_end = line('$')
    " Stop at the end of the enclosing module, rather than considering later
    " modules in the same file.
    if l:mod_start > 0
        for l:i in range(l:body_start, l:body_end)
            if getline(l:i) =~ '^\s*endmodule\>'
                let l:body_end = l:i - 1
                break
            endif
        endfor
    endif
    if l:body_start <= l:body_end
        for l:i in range(l:body_start, l:body_end)
            for l:name in s:DeclaredNamesFromLine(getline(l:i))
                let l:conflicts[l:name] = 1
            endfor
        endfor
    endif

    " If explicit named connections exist for instances of this module, reject
    " ports whose connection is not exactly the same simple identifier.
    let l:mismatches = s:GetMismatchedConnections(l:module, l:body_start, l:body_end)
    for l:name in keys(l:mismatches)
        let l:conflicts[l:name] = 1
    endfor

    let l:new_body = []
    let l:port_records = []
    let l:cond_stack = []
    let l:cond_id = 0
    for l:i in range(0, len(l:src_body) - 1)
        let l:raw = l:src_body[l:i]
        let l:clean = l:clean_src[l:i]
        let l:is_endif = l:clean =~ '^\s*`endif\>'
        if l:clean =~ '^\s*`\%(ifdef\|ifndef\)\>'
            let l:cond_id += 1
            call add(l:cond_stack, {'id': l:cond_id, 'branch': 0})
        elseif l:clean =~ '^\s*`\%(else\|elsif\)\>' && !empty(l:cond_stack)
            let l:cond_stack[-1].branch += 1
        endif

        let l:pname = s:PortNameFromLine(l:clean)
        if !empty(l:pname) && has_key(l:conflicts, l:pname)
            " Drop the conflicting port declaration, but keep every directive
            " (`ifdef/`else/`elsif/`endif) and all non-conflicting source lines.
            if l:is_endif && !empty(l:cond_stack)
                call remove(l:cond_stack, -1)
            endif
            continue
        endif

        let l:out = l:raw
        " A child output is a net driven by the child instance in this parent.
        " Replace only the output variable type; preserve signed/unsigned and packed widths.
        " Consume the whitespace after reg/logic so `output reg  signed` becomes
        " `output wire signed` without changing the rest of the source declaration.
        let l:out = substitute(l:out, '\<output\>\s\+reg\>\s\+', 'output wire ', 'g')
        let l:out = substitute(l:out, '\<output\>\s\+logic\>\s\+', 'output wire ', 'g')
        call add(l:new_body, l:out)
        if !empty(l:pname)
            let l:path = []
            for l:cond in l:cond_stack
                call add(l:path, [l:cond.id, l:cond.branch])
            endfor
            call add(l:port_records, {'line': len(l:new_body) - 1, 'path': l:path})
        endif
        if l:is_endif && !empty(l:cond_stack)
            call remove(l:cond_stack, -1)
        endif
    endfor

    " Remove commas from every possible last port in each preprocessor branch.
    " This avoids leaving a dangling comma when a later port was filtered out.
    for l:i in range(0, len(l:port_records) - 1)
        let l:has_later = 0
        for l:j in range(l:i + 1, len(l:port_records) - 1)
            if s:PathsCompatible(l:port_records[l:i].path, l:port_records[l:j].path)
                let l:has_later = 1
                break
            endif
        endfor
        if !l:has_later
            let l:line_idx = l:port_records[l:i].line
            let l:new_body[l:line_idx] = s:RemoveTrailingPortComma(l:new_body[l:line_idx])
        endif
    endfor

    " Align direction/type/width/name/comma/comment columns in the generated
    " region only. Source order and preprocessor lines are unchanged.
    let l:new_body = s:FormatPortLines(l:new_body)

    " Add PORT_NEW to newly generated port declarations. Only do this when an
    " old expansion contained at least one port, matching AUTOINST's behavior
    " for an initially empty instance-port list.
    if !empty(l:old_port_name_set) && !empty(l:new_body)
        for l:i in range(0, len(l:new_body) - 1)
            let l:new_name = s:PortNameFromLine(l:new_body[l:i])
            if !empty(l:new_name) && !has_key(l:old_port_name_set, l:new_name)
                let l:new_body[l:i] = s:AddPortChangeComment(l:new_body[l:i], 'PORT_NEW')
            endif
        endfor
    endif

    " Add one PORT_DEL record for each former generated port that no longer
    " exists in the child module's declaration. Deleted records are comments,
    " so they disappear naturally on the next update, just like AUTOINST.
    if !empty(l:old_port_name_set)
        let l:port_indent = matchstr(l:marker_text, '^\s*') . '    '
        if !empty(l:new_body)
            for l:i in range(0, len(l:new_body) - 1)
                if !empty(s:PortNameFromLine(l:new_body[l:i]))
                    let l:port_indent = matchstr(l:new_body[l:i], '^\s*')
                    break
                endif
            endfor
        endif
        for l:old_name in l:old_port_names
            if !has_key(l:source_port_name_set, l:old_name)
                call add(l:new_body, l:port_indent . '//PORT_DEL: Port ' . l:old_name . ' has been deleted.')
            endif
        endfor
    endif

    " Replace from immediately after the marker to the closing ')' only. The
    " bytes preceding the marker are written back unchanged.
    let l:prefix = strpart(l:marker_text, 0, l:marker_end)
    if empty(l:port_records)
        " A trailing comma before the marker cannot be fixed without violating
        " the explicit rule that text before AUTOPORT is immutable.
        for l:prior in reverse(copy(l:header_before))
            let l:prior_clean = s:StripComments([l:prior])[0]
            if !empty(s:PortNameFromLine(l:prior_clean))
                if l:prior_clean =~ ',\s*$'
                    echohl WarningMsg | echomsg 'AutoPort: all child ports were filtered; the manual port before AUTOPORT still has a comma. Remove that comma manually if this leaves an empty port list.' | echohl None
                endif
                break
            endif
        endfor
    endif
    let l:close_text = getline(l:close_line)
    let l:indent = matchstr(l:close_text, '^\s*')
    let l:suffix = strpart(l:close_text, l:close_col)
    let l:replacement = [l:prefix] + l:new_body + [l:indent . l:suffix]
    let l:old_span = l:close_line - a:marker_line

    call setline(a:marker_line, l:replacement[0])
    if len(l:replacement) > 1
        call append(a:marker_line, l:replacement[1:])
    endif
    " Appending inserted new lines before the old region; delete the shifted old
    " lines between the marker and original close line.
    if l:old_span > 0
        let l:delete_start = a:marker_line + len(l:replacement)
        let l:delete_end = l:delete_start + l:old_span - 1
        execute l:delete_start . ',' . l:delete_end . 'delete _'
    endif
endfunction

function! s:FindModuleFile(module) abort
    " Reuse automatic-verilog's existing project/file-list index when available.
    if exists('*g:AutoVerilog_GetModuleFileDirDic')
        try
            let [l:files, l:modules] = g:AutoVerilog_GetModuleFileDirDic()
            if has_key(l:modules, a:module)
                let l:file = l:modules[a:module]
                if has_key(l:files, l:file)
                    let l:path = l:files[l:file] . '/' . l:file
                    if filereadable(l:path)
                        return fnamemodify(l:path, ':p')
                    endif
                endif
            endif
        catch
            " Fall back to &path / filesystem search.
        endtry
    endif

    let l:file = findfile(a:module . '.v', &path)
    if !empty(l:file) && filereadable(l:file)
        return fnamemodify(l:file, ':p')
    endif
    for l:ext in ['v', 'sv']
        let l:file = findfile(a:module . '.' . l:ext, expand('%:p:h') . ',' . getcwd())
        if !empty(l:file) && filereadable(l:file)
            return fnamemodify(l:file, ':p')
        endif
    endfor

    " Recursive fallback from the current file directory and current working dir.
    let l:bases = [expand('%:p:h'), getcwd()]
    for l:base in l:bases
        if empty(l:base) | continue | endif
        let l:hits = split(globpath(l:base, '**/' . a:module . '.v'), "\n")
        if empty(l:hits) || (len(l:hits) == 1 && empty(l:hits[0]))
            let l:hits = split(globpath(l:base, '**/' . a:module . '.sv'), "\n")
        endif
        if !empty(l:hits) && filereadable(l:hits[0])
            return fnamemodify(l:hits[0], ':p')
        endif
    endfor
    return ''
endfunction

function! s:GetModulePortBody(lines, module) abort
    let l:text = join(a:lines, "\n")
    let l:offset = 0
    let l:module_line = -1
    let l:line_offsets = []
    for l:i in range(0, len(a:lines) - 1)
        call add(l:line_offsets, l:offset)
        let l:code = s:StripComments([a:lines[l:i]])[0]
        if l:code =~ '^\s*module\s\+' . escape(a:module, '\') . '\>'
            let l:module_line = l:offset + match(l:code, '\<module\>')
            break
        endif
        let l:offset += strlen(a:lines[l:i]) + 1
    endfor
    if l:module_line < 0
        return []
    endif
    let l:name_pat = '\<module\s\+' . escape(a:module, '\') . '\>'
    let l:name_end = matchend(l:text, l:name_pat, l:module_line)
    if l:name_end < 0
        return []
    endif
    let l:open = s:FindNextCodeParen(l:text, l:name_end)
    if l:open < 0
        return []
    endif
    let l:between = strpart(l:text, l:name_end, l:open - l:name_end)
    if l:between =~ '#'
        let l:param_close = s:FindMatchingParen(l:text, l:open)
        if l:param_close < 0
            return []
        endif
        let l:open = s:FindNextCodeParen(l:text, l:param_close + 1)
        if l:open < 0
            return []
        endif
    endif
    let l:close = s:FindMatchingParen(l:text, l:open)
    if l:close < 0
        return []
    endif
    let l:body = strpart(l:text, l:open + 1, l:close - l:open - 1)
    let l:body_lines = split(l:body, "\n", 1)
    if !empty(l:body_lines) && l:body_lines[0] =~ '^\s*$'
        call remove(l:body_lines, 0)
    endif
    if !empty(l:body_lines) && l:body_lines[-1] =~ '^\s*$'
        call remove(l:body_lines, -1)
    endif
    " A non-ANSI (old-style) header has no directions in the port list.
    let l:seen_port = 0
    for l:line in l:body_lines
        if l:line =~ '\<\(input\|output\|inout\)\>'
            let l:seen_port = 1
            break
        endif
    endfor
    return l:seen_port ? l:body_lines : []
endfunction

function! s:FindNextCodeParen(text, start) abort
    let l:i = a:start
    let l:n = strlen(a:text)
    let l:block = 0
    let l:string = 0
    while l:i < l:n
        let l:two = strpart(a:text, l:i, 2)
        let l:ch = strpart(a:text, l:i, 1)
        if l:block
            if l:two ==# '*/'
                let l:block = 0 | let l:i += 2 | continue
            endif
        elseif l:string
            if l:ch ==# '\\'
                let l:i += 2 | continue
            elseif l:ch ==# '"'
                let l:string = 0
            endif
        elseif l:two ==# '//'
            let l:nl = match(a:text, "\n", l:i)
            if l:nl < 0 | return -1 | endif
            let l:i = l:nl + 1 | continue
        elseif l:two ==# '/*'
            let l:block = 1 | let l:i += 2 | continue
        elseif l:ch ==# '"'
            let l:string = 1
        elseif l:ch ==# '('
            return l:i
        endif
        let l:i += 1
    endwhile
    return -1
endfunction

function! s:FindMatchingParen(text, open) abort
    if a:open < 0 | return -1 | endif
    let l:i = a:open
    let l:n = strlen(a:text)
    let l:depth = 0
    let l:block = 0
    let l:string = 0
    while l:i < l:n
        let l:two = strpart(a:text, l:i, 2)
        let l:ch = strpart(a:text, l:i, 1)
        if l:block
            if l:two ==# '*/'
                let l:block = 0 | let l:i += 2 | continue
            endif
        elseif l:string
            if l:ch ==# '\\'
                let l:i += 2 | continue
            elseif l:ch ==# '"'
                let l:string = 0
            endif
        elseif l:two ==# '//'
            let l:nl = match(a:text, "\n", l:i)
            if l:nl < 0 | return -1 | endif
            let l:i = l:nl + 1 | continue
        elseif l:two ==# '/*'
            let l:block = 1 | let l:i += 2 | continue
        elseif l:ch ==# '"'
            let l:string = 1
        elseif l:ch ==# '('
            let l:depth += 1
        elseif l:ch ==# ')'
            let l:depth -= 1
            if l:depth == 0
                return l:i
            endif
        endif
        let l:i += 1
    endwhile
    return -1
endfunction

function! s:FindCurrentHeaderClose(marker_line, marker_end) abort
    let l:marker_line_text = getline(a:marker_line)
    let l:close_pos = match(l:marker_line_text, ')\s*;', a:marker_end)
    if l:close_pos >= 0
        return [a:marker_line, l:close_pos]
    endif
    for l:i in range(a:marker_line + 1, line('$'))
        " The module port-list terminator is the first code `);` after marker.
        let l:code = s:StripComments([getline(l:i)])[0]
        let l:p = match(l:code, ')\s*;')
        if l:p >= 0
            return [l:i, l:p]
        endif
    endfor
    return []
endfunction

function! s:StripComments(lines) abort
    let l:out = []
    let l:block = 0
    for l:raw in a:lines
        let l:line = ''
        let l:i = 0
        let l:n = strlen(l:raw)
        while l:i < l:n
            let l:two = strpart(l:raw, l:i, 2)
            let l:ch = strpart(l:raw, l:i, 1)
            if l:block
                if l:two ==# '*/'
                    let l:block = 0 | let l:line .= '  ' | let l:i += 2 | continue
                endif
                let l:line .= ' '
            elseif l:two ==# '//'
                let l:line .= repeat(' ', l:n - l:i)
                break
            elseif l:two ==# '/*'
                let l:block = 1 | let l:line .= '  ' | let l:i += 2 | continue
            else
                let l:line .= l:ch
            endif
            let l:i += 1
        endwhile
        call add(l:out, l:line)
    endfor
    return l:out
endfunction

function! s:PortNameFromLine(line) abort
    " Always remove comments before parsing the declaration. In particular,
    " manual ports often have trailing timing comments such as
    "   input wire foo, // negedge clk
    " Without stripping the comment, the final word in the comment can be
    " mistaken for the port name, allowing a duplicate AUTOPORT declaration.
    let l:s = s:StripComments([a:line])[0]
    let l:s = substitute(l:s, '\s*$', '', '')
    if l:s =~ '^\s*`' || l:s =~ '^\s*$'
        return ''
    endif
    if l:s !~ '\<\(input\|output\|inout\)\>'
        return ''
    endif
    " Ignore packed dimensions and the trailing comma before taking the final id.
    let l:s = substitute(l:s, '\[[^]]*\]', '', 'g')
    let l:s = substitute(l:s, ',\s*$', '', '')
    let l:name = matchstr(l:s, '\h\w*\s*$')
    return substitute(l:name, '\s', '', 'g')
endfunction

function! s:DeclaredNamesFromLine(line) abort
    let l:clean = s:StripComments([a:line])[0]
    if l:clean =~ '^\s*`' || l:clean !~ '^\s*\(input\|output\|inout\|wire\|reg\|logic\|bit\|tri\|tri0\|tri1\|wand\|wor\|integer\|time\|genvar\|parameter\|localparam\|event\)\>'
        return []
    endif
    " A declaration may contain several comma-separated names. Widths and
    " unpacked dimensions are removed before taking each segment's final id.
    let l:work = substitute(l:clean, '^\s*\(input\|output\|inout\|wire\|reg\|logic\|bit\|tri\|tri0\|tri1\|wand\|wor\|integer\|time\|genvar\|parameter\|localparam\|event\)\>', '', '')
    let l:work = substitute(l:work, '\<\(wire\|reg\|logic\|bit\|signed\|unsigned\|var\|const\)\>', '', 'g')
    let l:work = substitute(l:work, '\[[^]]*\]', '', 'g')
    let l:segs = split(l:work, ',')
    let l:names = []
    for l:seg in l:segs
        let l:seg = substitute(l:seg, '=.*$', '', '')
        let l:name = matchstr(l:seg, '\h\w*\s*;\?\s*$')
        let l:name = substitute(l:name, '[;[:space:]]', '', 'g')
        if !empty(l:name)
            call add(l:names, l:name)
        endif
    endfor
    return l:names
endfunction

function! s:AddPortChangeComment(line, tag) abort
    " Append the tag to an existing // comment if present; otherwise add a
    " new trailing line comment. This keeps original source comments intact.
    if a:line =~# '\<' . a:tag . '\>'
        return a:line
    endif
    let l:comment_pos = match(a:line, '//')
    if l:comment_pos >= 0
        return a:line . ' ' . a:tag
    endif
    return a:line . ' //' . a:tag
endfunction

" -----------------------------------------------------------------------------
" Align generated port declaration columns without reordering any lines.
"
" Format policy:
"   indent + direction padded to 6 columns + type/width + port name + comma
"   signed/unsigned and macro expressions are retained verbatim.
"   comments and all preprocessor/non-port lines are retained.
" -----------------------------------------------------------------------------
function! s:FormatPortLines(lines) abort
    let l:entries = {}
    let l:max_prefix = 0
    let l:max_name = 0

    for l:i in range(0, len(a:lines) - 1)
        let l:raw = a:lines[l:i]
        let l:clean = s:StripComments([l:raw])[0]
        let l:clean = substitute(l:clean, '\s*$', '', '')
        let l:pname = s:PortNameFromLine(l:clean)

        if empty(l:pname)
            continue
        endif

        let l:comment_pos = match(l:raw, '//')
        if l:comment_pos < 0
            let l:comment_pos = match(l:raw, '/\*')
        endif
        let l:comment = l:comment_pos >= 0 ? strpart(l:raw, l:comment_pos) : ''

        let l:has_comma = l:clean =~ ',\s*$'
        let l:code = l:clean
        if l:has_comma
            let l:code = substitute(l:code, ',\s*$', '', '')
        endif
        " The original RTL often pads port names with spaces before the comma.
        " Remove that padding before locating the identifier.
        let l:code = substitute(l:code, '\s\+$', '', '')

        let l:indent = matchstr(l:code, '^\s*')
        let l:after_indent = strpart(l:code, strlen(l:indent))
        let l:direction = matchstr(l:after_indent, '^\%(input\|output\|inout\)\>')
        if empty(l:direction)
            continue
        endif

        let l:dir_end = strlen(l:indent) + strlen(l:direction)
        let l:name_pos = match(l:code, '\h\w*$')
        if l:name_pos < l:dir_end
            continue
        endif
        let l:name = strpart(l:code, l:name_pos)

        let l:type_part = strpart(l:code, l:dir_end, l:name_pos - l:dir_end)
        let l:type_part = substitute(l:type_part, '^\s\+', '', '')
        let l:type_part = substitute(l:type_part, '\s\+$', '', '')

        let l:prefix = l:indent . printf('%-6s', l:direction)
        if !empty(l:type_part)
            let l:prefix .= ' ' . l:type_part
        endif
        let l:prefix = substitute(l:prefix, '\s\+$', '', '')

        let l:entries[string(l:i)] = {
                    \ 'prefix': l:prefix,
                    \ 'name': l:name,
                    \ 'comma': l:has_comma,
                    \ 'comment': l:comment
                    \ }
        let l:max_prefix = max([l:max_prefix, strlen(l:prefix)])
        let l:max_name = max([l:max_name, strlen(l:name)])
    endfor

    if empty(l:entries)
        return copy(a:lines)
    endif

    let l:name_col = l:max_prefix + 1
    let l:comma_col = l:name_col + l:max_name + 1
    let l:comment_col = l:comma_col + 2
    let l:out = copy(a:lines)

    for l:key in keys(l:entries)
        let l:e = l:entries[l:key]
        let l:line = l:e.prefix
                    \ . repeat(' ', max([1, l:name_col - strlen(l:e.prefix)]))
                    \ . l:e.name

        if l:e.comma
            let l:line .= repeat(' ', max([1, l:comma_col - strlen(l:line)])) . ','
        endif

        if !empty(l:e.comment)
            let l:line .= repeat(' ', max([1, l:comment_col - strlen(l:line)]))
                    \ . l:e.comment
        endif

        let l:out[str2nr(l:key)] = l:line
    endfor

    return l:out
endfunction


function! s:PathsCompatible(path_a, path_b) abort
    for l:a in a:path_a
        for l:b in a:path_b
            if l:a[0] == l:b[0] && l:a[1] != l:b[1]
                return 0
            endif
        endfor
    endfor
    return 1
endfunction

function! s:RemoveTrailingPortComma(line) abort
    let l:idx = match(a:line, ',\s*\%(//.*\)\?$')
    if l:idx < 0
        return a:line
    endif
    let l:tail = strpart(a:line, l:idx + 1)
    let l:tail = substitute(l:tail, '^\s*', '', '')
    return strpart(a:line, 0, l:idx) . (empty(l:tail) ? '' : ' ' . l:tail)
endfunction

function! s:GetMismatchedConnections(module, body_start, body_end) abort
    let l:bad = {}
    if a:body_start > a:body_end
        return l:bad
    endif
    let l:raw_lines = getline(a:body_start, a:body_end)
    let l:text = join(s:StripComments(l:raw_lines), "\n")
    let l:module_pat = '\<' . escape(a:module, '\') . '\>'
    let l:search_from = 0
    while 1
        " Common form: child_module instance_name (...).
        let l:inst_start = match(l:text, l:module_pat . '\s\+\h\w*\s*(', l:search_from)
        if l:inst_start < 0
            " Parameterized form: child_module #(...) instance_name (...).
            let l:hash_start = match(l:text, l:module_pat . '\s*#\s*(', l:search_from)
            if l:hash_start < 0
                break
            endif
            let l:param_open = match(l:text, '(', l:hash_start)
            let l:param_close = s:FindMatchingParen(l:text, l:param_open)
            if l:param_close < 0 | break | endif
            let l:after_param = l:param_close + 1
            let l:inst_name_end = matchend(l:text, '\s*\h\w*\s*(', l:after_param)
            if l:inst_name_end < 0
                let l:search_from = l:param_close + 1
                continue
            endif
            let l:port_open = match(l:text, '(', l:after_param)
            let l:inst_start = l:hash_start
        else
            let l:port_open = match(l:text, '(', l:inst_start)
        endif
        let l:port_close = s:FindMatchingParen(l:text, l:port_open)
        if l:port_close < 0
            break
        endif
        let l:ports = strpart(l:text, l:port_open + 1, l:port_close - l:port_open - 1)
        let l:psearch = 0
        while 1
            let l:pstart = match(l:ports, '\.\h\w*\s*(', l:psearch)
            if l:pstart < 0 | break | endif
            let l:pname = matchstr(strpart(l:ports, l:pstart), '^\.\zs\h\w*')
            let l:open_rel = match(l:ports, '(', l:pstart)
            let l:conn_close = s:FindMatchingParen(l:ports, l:open_rel)
            if l:conn_close < 0 | break | endif
            let l:conn = strpart(l:ports, l:open_rel + 1, l:conn_close - l:open_rel - 1)
            let l:conn = substitute(l:conn, '^\s*', '', '')
            let l:conn = substitute(l:conn, '\s*$', '', '')
            if l:conn !~ '^\h\w*$' || l:conn !=# l:pname
                let l:bad[l:pname] = 1
            endif
            let l:psearch = l:conn_close + 1
        endwhile
        let l:search_from = l:port_close + 1
    endwhile
    return l:bad
endfunction