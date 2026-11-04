" -----------------------------------------------------------------------------
" AUTOPORT for HonkW93/automatic-verilog
" File: plugin/automatic/autoport.vim
" Purpose:
"   Generate the parent module's ports from a named child module while leaving
"   all text before /*AUTOPORT(module)*/ untouched.
"
" Supported markers:
"   /*AUTOPORT(a)*/
"   /**AUTOPORT(a)**/
"   (one or more asterisks around AUTOPORT are accepted)
"   Multiple markers in one module header own separate expansion regions.
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
"   - For connection analysis, expand AUTOINST first so explicit named-port
"     connections are visible to this script.
"   - Emits AUTOPORT_UNUSED comments for unused mismatched, open and missing
"     named-port connections; repeated instances of the same child are not
"     aggregated, and positional connection lists are not analyzed.
"   - Removes standalone source comments and blank rows from the copied port
"     list while retaining comments attached to port declarations.
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
    amenu 9998.2.2 &Verilog.&AutoPort.AutoPort(1)\ \ \ \ \ \ \ \ \ \ \ \ \ All :call g:AutoPort(1)<CR>
    amenu 9998.2.3 &Verilog.&AutoPort.KillAutoPort(0)\ \ \ \ \ \ One :call g:KillAutoPort(0)<CR>
    amenu 9998.2.4 &Verilog.&AutoPort.KillAutoPort(1)\ \ \ \ \ \ \ \ All :call g:KillAutoPort(1)<CR>
endif

let s:autop_marker_pat = '/\*\+\s*AUTOPORT\s*(\s*\h\w*\s*)\s*\*\+/'

" AutoPort Config 自动端口格式配置
"   st_pos   : generated port declaration start column
"   name_pos : port-name start column
"   sym_pos  : trailing comma column
let g:_ATV_AUTOPORT_DEFAULTS = {
            \ 'st_pos':      4,
            \ 'name_pos':    64,
            \ 'sym_pos':     128
            \ }
for s:key in keys(g:_ATV_AUTOPORT_DEFAULTS)
    if !exists('g:atv_autoport_' . s:key)
        let g:atv_autoport_{s:key} = copy(g:_ATV_AUTOPORT_DEFAULTS[s:key])
    endif
endfor

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
        " Move to end of this line. Starting at column 1 of the next line
        " would make search() skip an AUTOPORT marker at that column.
        call cursor(line('.'), col('$'))
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
        " Move to end of this line. Starting at column 1 of the next line
        " would make search() skip an AUTOPORT marker at that column.
        call cursor(line('.'), col('$'))
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

    let l:header_close = s:FindCurrentHeaderClose(a:marker_line, l:marker_end)
    if empty(l:header_close)
        echohl ErrorMsg | echomsg 'KillAutoPort: cannot find closing ); for marker at line ' . a:marker_line | echohl None
        return
    endif
    let l:boundary = s:FindAutoPortBoundary(a:marker_line, l:marker_end, l:header_close)
    if empty(l:boundary)
        echohl ErrorMsg | echomsg 'KillAutoPort: cannot determine expansion boundary at line ' . a:marker_line | echohl None
        return
    endif

    if l:boundary.kind ==# 'marker'
        if l:boundary.line == a:marker_line
            " Two markers share one line. There cannot be a multi-line generated
            " expansion between them, so preserve the complete marker line.
            return
        endif
        let l:prefix = strpart(l:marker_text, 0, l:marker_end)
        call setline(a:marker_line, l:prefix)
        let l:first = a:marker_line + 1
        let l:last = l:boundary.line - 1
        if l:first <= l:last
            execute l:first . ',' . l:last . 'delete _'
        endif
        return
    endif

    " Last AUTOPORT marker in this header: remove through the header's `);`.
    let l:close_line = l:boundary.line
    let l:close_col = l:boundary.col
    let l:prefix = strpart(l:marker_text, 0, l:marker_end)
    let l:close_text = getline(l:close_line)
    let l:suffix = strpart(l:close_text, l:close_col)
    let l:close_replacement = matchstr(l:close_text, '^\s*') . l:suffix

    call setline(a:marker_line, l:prefix)
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

    let l:header_close = s:FindCurrentHeaderClose(a:marker_line, l:marker_end)
    if empty(l:header_close)
        echohl ErrorMsg | echomsg 'AutoPort: cannot find closing ); for marker at line ' . a:marker_line | echohl None
        return
    endif
    let l:boundary = s:FindAutoPortBoundary(a:marker_line, l:marker_end, l:header_close)
    if empty(l:boundary)
        echohl ErrorMsg | echomsg 'AutoPort: cannot determine expansion boundary at line ' . a:marker_line | echohl None
        return
    endif
    let l:close_line = l:boundary.line
    let l:close_col = l:boundary.col
    let l:header_close_line = l:header_close[0]

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

    " Find the enclosing module declaration first. Do not treat ports from a
    " previous module in the same file as conflicts.
    let l:mod_start = a:marker_line
    while l:mod_start > 1 && s:StripComments([getline(l:mod_start)])[0] !~ '^\s*module\>'
        let l:mod_start -= 1
    endwhile

    " Only text before the FIRST AUTOPORT marker is considered hand-written
    " module-header content. Earlier AUTOPORT expansions are generated text,
    " not manual declarations and must not suppress another region's candidate.
    let l:first_marker_line = -1
    let l:first_marker_col = -1
    for l:i in range(l:mod_start, a:marker_line)
        let l:pos = match(getline(l:i), s:autop_marker_pat)
        if l:pos >= 0
            let l:first_marker_line = l:i
            let l:first_marker_col = l:pos
            break
        endif
    endfor
    let l:header_before = []
    if l:first_marker_line >= 0
        if l:first_marker_line > l:mod_start
            let l:header_before = getline(l:mod_start, l:first_marker_line - 1)
        endif
        call add(l:header_before, strpart(getline(l:first_marker_line), 0, l:first_marker_col))
    else
        if l:mod_start < a:marker_line
            let l:header_before = getline(l:mod_start, a:marker_line - 1)
        endif
        call add(l:header_before, strpart(l:marker_text, 0, l:marker_start))
    endif

    " Conflict set = hand-written ports before the first AUTOPORT marker +
    " declarations/assignments in this module body. Other AUTOPORT regions are
    " deliberately excluded; duplicate detection is performed from instances.
    let l:conflicts = {}
    for l:line in l:header_before
        let l:pname = s:PortNameFromLine(l:line)
        if !empty(l:pname)
            let l:conflicts[l:pname] = 1
        endif
    endfor

    let l:body_start = l:header_close_line + 1
    let l:body_end = l:body_start - 1
    let l:body_raw_lines = []
    let l:body_clean_lines = []

    " Read and clean each parent-body line once, stopping at this module's
    " endmodule. Reuse the cached lines for conflicts and signal-use analysis.
    if l:body_start <= line('$')
        for l:i in range(l:body_start, line('$'))
            let l:raw_line = getline(l:i)
            let l:clean_line = s:StripComments([l:raw_line])[0]
            if l:mod_start > 0 && l:clean_line =~ '^\s*endmodule\>'
                break
            endif
            call add(l:body_raw_lines, l:raw_line)
            call add(l:body_clean_lines, l:clean_line)
            let l:body_end = l:i
        endfor
    endif

    " AutoPortGetCodeText() is the expensive lexical pass. Share its result
    " among duplicate detection, instance-connection parsing and usage index.
    let l:body_code_text = s:AutoPortGetCodeText(l:body_raw_lines)

    let l:body_declared_names = {}
    let l:body_declared_counts = {}
    for l:i in range(0, len(l:body_raw_lines) - 1)
        " Explicit declarations are conflicts as before. Keep their names
        " separately so an unused same-name wire/reg can be annotated.
        let l:decl_clean = l:body_clean_lines[l:i]
        let l:is_net_reg_decl = l:decl_clean =~# '^\s*\%(wire\|reg\|logic\|bit\|tri\|tri0\|tri1\|wand\|wor\)\>'
        for l:name in s:DeclaredNamesFromLine(l:decl_clean, 1)
            let l:conflicts[l:name] = 1
            let l:body_declared_counts[l:name] = get(l:body_declared_counts, l:name, 0) + 1
            if l:is_net_reg_decl
                let l:body_declared_names[l:name] = 1
            endif
        endfor
        " Also treat assignment LHS names as locally driven signals.
        " This catches undeclared procedural variables such as:
        "   rd_motion_tggl <= 'd0;
        " which must not be regenerated as a parent input port.
        for l:name in s:AssignedNamesFromLine(l:decl_clean, 1)
            let l:conflicts[l:name] = 1
        endfor
    endfor

    " Scan every instance in the current module, including instances that do
    " not have an AUTOPORT marker. Conditional-compilation branches are all
    " scanned without trying to prove them mutually exclusive.
    let l:duplicate_names = s:AutoPortFindDuplicateConnections(l:body_start, l:body_end, l:body_code_text)

    " Build the parent signal-usage index once. Every AUTOPORT candidate then
    " performs constant-time dictionary lookups instead of rescanning the full
    " parent module for each signal.
    let l:signal_usage_index = s:AutoPortBuildSignalUsageIndex(
                \ l:body_start, l:body_end, l:header_before, l:body_code_text, l:body_raw_lines, l:body_declared_counts)

    " Keep the parent/manual conflicts separately. Later-region comma planning
    " must apply each later child module's own mismatch set, not this marker's.
    let l:base_conflicts = copy(l:conflicts)

    " Read the target instance's named-port connections. This also lets us
    " distinguish an explicitly open connection from a missing named port.
    let l:connections = s:GetInstancePortConnections(l:module, l:body_start, l:body_end, l:body_code_text)
    for l:name in keys(l:connections.ports)
        if l:connections.ports[l:name].kind !=# 'match'
            let l:conflicts[l:name] = 1
        endif
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
        if !empty(l:pname)
            let l:conn_info = get(l:connections.ports, l:pname, {})

            " Case 3: the target instance explicitly writes .port().
            if !empty(l:conn_info) && l:conn_info.kind ==# 'open'
                call extend(l:new_body, s:AutoPortUnusedCommentLines(l:raw, ' (open)'))
                if l:is_endif && !empty(l:cond_stack)
                    call remove(l:cond_stack, -1)
                endif
                continue
            endif

            " Case 4: a recognized named-port list omits this child port.
            " Do not infer missing ports from positional connection lists.
            if l:connections.recognized && !l:connections.wildcard && empty(l:conn_info)
                call extend(l:new_body, s:AutoPortUnusedCommentLines(l:raw, ' (missing)'))
                if l:is_endif && !empty(l:cond_stack)
                    call remove(l:cond_stack, -1)
                endif
                continue
            endif

            " Case 1: a different simple signal name is connected, but that
            " signal has no use elsewhere in this parent module.
            if !empty(l:conn_info) && l:conn_info.kind ==# 'mismatch'
                if l:conn_info.conn =~# '^\h\w*$'
                            \ && !s:AutoPortSignalHasOtherUse(l:signal_usage_index, l:conn_info.conn,
                            \                                  get(l:conn_info, 'exclude', 1))
                    call extend(l:new_body, s:AutoPortUnusedCommentLines(
                                \ l:raw, ' -> ' . l:conn_info.conn))
                endif
                if l:is_endif && !empty(l:cond_stack)
                    call remove(l:cond_stack, -1)
                endif
                continue
            endif

            " Case 2: a same-name wire/reg declaration already suppresses
            " the generated port, and the signal has no other use.
            " Keep the original conflict-before-duplicate priority.
            if has_key(l:conflicts, l:pname)
                let l:same_name_connected = (!empty(l:conn_info)
                            \ && l:conn_info.kind ==# 'match') || l:connections.wildcard
                if l:same_name_connected && has_key(l:body_declared_names, l:pname)
                            \ && !s:AutoPortSignalHasOtherUse(l:signal_usage_index, l:pname,
                            \                                  get(l:conn_info, 'exclude', 0))
                    call extend(l:new_body, s:AutoPortUnusedCommentLines(l:raw, ''))
                endif
                if l:is_endif && !empty(l:cond_stack)
                    call remove(l:cond_stack, -1)
                endif
                continue
            endif

            " Preserve the existing duplicate-comment behavior after ordinary
            " parent conflicts have been checked.
            if has_key(l:duplicate_names, l:pname)
                let l:duplicate_line = s:AutoPortDuplicateComment(l:raw)
                if !empty(l:duplicate_line)
                    call add(l:new_body, l:duplicate_line)
                endif
                if l:is_endif && !empty(l:cond_stack)
                    call remove(l:cond_stack, -1)
                endif
                continue
            endif
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

    " Determine whether any later AUTOPORT region will actually emit at least
    " one active port. Do not infer this from stale text left by a previous run.
    let l:has_later_region_ports = s:AutoPortHasLaterRegionPorts(
                \ l:boundary, l:header_close, l:base_conflicts, l:duplicate_names,
                \ l:body_start, l:body_end, l:body_code_text)

    " Remove/add commas from every possible last port in each preprocessor
    " branch, taking later AUTOPORT regions into account.
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
            if l:has_later_region_ports
                let l:new_body[l:line_idx] = s:EnsureTrailingPortComma(l:new_body[l:line_idx])
            else
                let l:new_body[l:line_idx] = s:RemoveTrailingPortComma(l:new_body[l:line_idx])
            endif
        endif
    endfor

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

    " Align direction/type/width/name/comma/comment columns in the generated
    " region only. Source order and preprocessor lines are unchanged.
    let l:new_body = s:FormatPortLines(l:new_body)

    " Add one PORT_DEL record for each former generated port that no longer
    " exists in the child module's declaration. Deleted records are comments,
    " so they disappear naturally on the next update, just like AUTOINST.
    if !empty(l:old_port_name_set)
        let l:port_indent = repeat(' ', max([0, g:atv_autoport_st_pos]))
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

    " Replace only this marker's region. If another AUTOPORT marker follows in
    " the same module header, leave that marker and its expansion untouched.
    let l:prefix = strpart(l:marker_text, 0, l:marker_end)
    if empty(l:port_records) && !l:has_later_region_ports
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

    let l:old_span = l:close_line - a:marker_line
    if l:boundary.kind ==# 'marker'
        if l:close_line == a:marker_line
            " Same-line markers: preserve the second marker as a separate line.
            let l:between = strpart(l:marker_text, l:marker_end, l:close_col - l:marker_end)
            let l:after = strpart(l:marker_text, l:close_col)
            if empty(l:new_body)
                call setline(a:marker_line, l:prefix . l:between . l:after)
            else
                call setline(a:marker_line, l:prefix)
                call append(a:marker_line, l:new_body + [l:between . l:after])
            endif
        else
            call setline(a:marker_line, l:prefix)
            if !empty(l:new_body)
                call append(a:marker_line, l:new_body)
            endif
            let l:old_count = l:close_line - a:marker_line - 1
            let l:delete_start = a:marker_line + len(l:new_body) + 1
            let l:delete_end = l:delete_start + l:old_count - 1
            if l:old_count > 0
                execute l:delete_start . ',' . l:delete_end . 'delete _'
            endif
        endif
    else
        " Last marker before `);`: keep the original header terminator intact.
        let l:close_text = getline(l:close_line)
        let l:indent = matchstr(l:close_text, '^\s*')
        let l:suffix = strpart(l:close_text, l:close_col)
        let l:close_replacement = l:indent . l:suffix
        call setline(a:marker_line, l:prefix)
        if !empty(l:new_body)
            call append(a:marker_line, l:new_body)
        endif
        let l:old_count = l:close_line - a:marker_line - 1
        let l:delete_start = a:marker_line + len(l:new_body) + 1
        let l:delete_end = l:delete_start + l:old_count - 1
        if l:old_count > 0
            execute l:delete_start . ',' . l:delete_end . 'delete _'
        endif
        call setline(a:marker_line + len(l:new_body) + 1, l:close_replacement)
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
    return l:seen_port ? s:AutoPortCleanPortBody(l:body_lines) : []
endfunction

function! s:AutoPortCleanPortBody(lines) abort
    " Remove blank rows and rows containing only comments. Preserve comments
    " attached to code, including a multi-line block comment opened inline.
    let l:out = []
    let l:block = 0
    let l:block_keep = 0

    for l:raw in a:lines
        let l:keep_line = 0
        let l:i = 0
        let l:n = strlen(l:raw)

        if l:block && l:block_keep
            let l:keep_line = 1
        endif

        while l:i < l:n
            let l:two = strpart(l:raw, l:i, 2)
            let l:ch = strpart(l:raw, l:i, 1)

            if l:block
                if l:two ==# '*/'
                    let l:block = 0
                    let l:block_keep = 0
                    let l:i += 2
                    continue
                endif
                let l:i += 1
                continue
            endif

            if l:two ==# '//'
                " A line comment is retained only when code preceded it.
                break
            elseif l:two ==# '/*'
                if strpart(l:raw, 0, l:i) =~# '\S'
                    let l:keep_line = 1
                    let l:block_keep = 1
                else
                    let l:block_keep = 0
                endif
                let l:block = 1
                let l:i += 2
                continue
            elseif l:ch =~# '\S'
                let l:keep_line = 1
            endif
            let l:i += 1
        endwhile

        if l:keep_line
            call add(l:out, l:raw)
        endif
    endfor

    return l:out
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

function! s:FindAutoPortBoundary(marker_line, marker_end, header_close) abort
    let l:next = s:FindNextAutoPortMarker(a:marker_line, a:marker_end)
    if !empty(l:next)
        if l:next[0] < a:header_close[0]
                    \ || (l:next[0] == a:header_close[0] && l:next[1] < a:header_close[1])
            return {'line': l:next[0], 'col': l:next[1], 'kind': 'marker'}
        endif
    endif
    return {'line': a:header_close[0], 'col': a:header_close[1], 'kind': 'close'}
endfunction

function! s:FindNextAutoPortMarker(marker_line, marker_end) abort
    let l:lnum = a:marker_line
    let l:start = a:marker_end
    while l:lnum <= line('$')
        let l:text = getline(l:lnum)
        let l:pos = match(l:text, s:autop_marker_pat, l:start)
        if l:pos >= 0 && l:text !~ '^\s*//'
            return [l:lnum, l:pos]
        endif
        let l:lnum += 1
        let l:start = 0
    endwhile
    return []
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

function! s:DeclaredNamesFromLine(line, ...) abort
    let l:clean = a:0 >= 1 && a:1 ? a:line : s:StripComments([a:line])[0]
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

function! s:AssignedNamesFromLine(line, ...) abort
    " Identify simple procedural/continuous assignment targets on a line.
    " Examples:
    "   rd_motion_tggl <= 'd0;
    "   if (rst_n) rd_motion_tggl <= 1'b1;
    "   count = count + 1;
    "   data[7:0] <= value;
    "   {valid, ready} <= 2'b0;
    " This is intentionally a lightweight line-oriented parser rather than
    " a complete Verilog grammar. Complex/multiline lvalues are not inferred.
    let l:work = a:0 >= 1 && a:1 ? a:line : s:StripComments([a:line])[0]
    if l:work =~ '^\s*`'
        return []
    endif

    " For a one-line `if (condition) statement`, skip the condition first.
    " This prevents a relational `<=` inside the condition from looking like
    " a nonblocking assignment, while still detecting the statement's LHS.
    let l:work = substitute(l:work, '^\s*else\s*', '', '')
    if l:work =~ '^\s*if\>'
        let l:open = match(l:work, '(')
        if l:open >= 0
            let l:depth = 0
            let l:close = -1
            for l:i in range(l:open, strlen(l:work) - 1)
                let l:ch = strpart(l:work, l:i, 1)
                if l:ch ==# '('
                    let l:depth += 1
                elseif l:ch ==# ')'
                    let l:depth -= 1
                    if l:depth == 0
                        let l:close = l:i
                        break
                    endif
                endif
            endfor
            if l:close >= 0
                let l:work = strpart(l:work, l:close + 1)
            else
                return []
            endif
        else
            return []
        endif
    endif

    " Allow a continuous-assign prefix.
    let l:work = substitute(l:work, '^\s*assign\s\+', '', '')

    " Find <= (nonblocking), common compound assignments, or a standalone =.
    " The standalone form excludes equality/relational operators.
    let l:op = match(l:work, '\%(<<=\|>>=\|<=\|+=\|-=\|\*=\|/=\|%=\|&=\||=\|\^=\|\%([!<>=]\)\@<! =\%([=>]\)\@!\)')
    if l:op < 0
        return []
    endif
    let l:lhs = substitute(strpart(l:work, 0, l:op), '^\s*', '', '')
    let l:lhs = substitute(l:lhs, '\s*$', '', '')
    if empty(l:lhs)
        return []
    endif

    " Accept a simple identifier/bit-select, or a concatenation of them.
    let l:simple_lvalue = '^\h\w*\%(\s*\[[^]]*\]\)\?\s*$'
    let l:concat_lvalue = '^\s*{\s*\h\w*\%(\s*\[[^]]*\]\)\?\%(\s*,\s*\h\w*\%(\s*\[[^]]*\]\)\?\)*\s*}\s*$'
    if l:lhs !~# l:simple_lvalue && l:lhs !~# l:concat_lvalue
        return []
    endif

    " Index expressions do not name the assigned object (data[addr] writes
    " data, not addr), so remove bracketed selects before collecting ids.
    let l:lhs = substitute(l:lhs, '\[[^]]*\]', '', 'g')
    let l:names = []
    let l:pos = 0
    while 1
        let l:start = match(l:lhs, '\h\w*', l:pos)
        if l:start < 0
            break
        endif
        let l:name = matchstr(l:lhs, '\h\w*', l:pos)
        call add(l:names, l:name)
        let l:pos = l:start + strlen(l:name)
    endwhile
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
"   st_pos controls the declaration indentation.
"   name_pos controls the minimum port-name column.
"   sym_pos controls the minimum trailing-comma column.
"   Longer declarations/names extend the following columns as needed.
"   comments and all preprocessor/non-port lines are retained.
" -----------------------------------------------------------------------------
function! s:FormatPortLines(lines) abort
    let l:entries = {}
    let l:max_decl_len = 0
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
        let l:code = l:has_comma ? substitute(l:clean, ',\s*$', '', '') : l:clean
        let l:code = substitute(l:code, '\s\+$', '', '')
        let l:source_indent = matchstr(l:code, '^\s*')
        let l:after_indent = strpart(l:code, strlen(l:source_indent))
        let l:direction = matchstr(l:after_indent, '^\%(input\|output\|inout\)\>')
        if empty(l:direction)
            continue
        endif

        let l:dir_end = strlen(l:source_indent) + strlen(l:direction)
        let l:name_pos = match(l:code, '\h\w*$')
        if l:name_pos < l:dir_end
            continue
        endif
        let l:name = strpart(l:code, l:name_pos)
        let l:type_part = strpart(l:code, l:dir_end, l:name_pos - l:dir_end)
        let l:type_part = substitute(l:type_part, '^\s\+', '', '')
        let l:type_part = substitute(l:type_part, '\s\+$', '', '')
        let l:type_part = substitute(l:type_part, '\s\+', ' ', 'g')

        " Canonical packed-range spacing:
        "   wire[W:0], wire signed[W:0], reg [W:0].
        " Remove whitespace before '[' generally, then restore exactly one
        " space only for an unsigned or signed reg token immediately before it.
        let l:type_part = substitute(l:type_part, '\s*\[', '[', 'g')
        let l:type_part = substitute(l:type_part, '\<reg\>\[', 'reg [', 'g')

        " Direction spacing is intentionally literal and independent of type.
        if l:direction ==# 'output'
            let l:dir_gap = ' '
        else
            let l:dir_gap = '  '
        endif
        let l:decl = repeat(' ', max([0, g:atv_autoport_st_pos]))
                    \ . l:direction . l:dir_gap . l:type_part

        let l:entries[string(l:i)] = {
                    \ 'decl': l:decl,
                    \ 'name': l:name,
                    \ 'comma': l:has_comma,
                    \ 'comment': l:comment
                    \ }
        let l:max_decl_len = max([l:max_decl_len, strlen(l:decl)])
        let l:max_name = max([l:max_name, strlen(l:name)])
    endfor

    if empty(l:entries)
        return copy(a:lines)
    endif

    " Keep port names vertically aligned, without aligning '[' columns.
    let l:name_col = max([l:max_decl_len + 1, g:atv_autoport_name_pos])
    let l:comma_col = max([l:name_col + l:max_name + 1, g:atv_autoport_sym_pos])
    let l:comment_col = l:comma_col + 2
    let l:out = copy(a:lines)

    for l:key in keys(l:entries)
        let l:e = l:entries[l:key]
        let l:line = l:e.decl . repeat(' ', max([1, l:name_col - strlen(l:e.decl)])) . l:e.name

        if l:e.comma
            let l:line .= repeat(' ', max([1, l:comma_col - strlen(l:line)])) . ','
        endif
        if !empty(l:e.comment)
            let l:line .= repeat(' ', max([1, l:comment_col - strlen(l:line)])) . l:e.comment
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

function! s:EnsureTrailingPortComma(line) abort
    if a:line =~ ',\s*\%(//.*\)\?$'
        return a:line
    endif
    let l:comment_pos = match(a:line, '//')
    if l:comment_pos >= 0
        let l:before = substitute(strpart(a:line, 0, l:comment_pos), '\s\+$', '', '')
        let l:after = strpart(a:line, l:comment_pos)
        return l:before . ',' . (empty(l:after) ? '' : ' ' . l:after)
    endif
    return substitute(a:line, '\s\+$', '', '') . ','
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

function! s:GetInstancePortConnections(module, body_start, body_end, ...) abort
    " Parse the first named-port instance of a child module in the parent body.
    " Multiple instances are intentionally outside the current AUTOPORT policy.
    let l:result = {'recognized': 0, 'wildcard': 0, 'ports': {}}
    if a:body_start > a:body_end
        return l:result
    endif

    let l:text = a:0 >= 1 ? a:1 : s:AutoPortGetCodeText(getline(a:body_start, a:body_end))
    let l:module_pat = '\<' . escape(a:module, '\') . '\>'
    let l:plain_pat = l:module_pat . '\_s\+\h\w*\_s*('
    let l:hash_pat = l:module_pat . '\_s*#\_s*('
    let l:plain_pos = match(l:text, l:plain_pat)
    let l:hash_pos = match(l:text, l:hash_pat)

    if l:plain_pos < 0 && l:hash_pos < 0
        return l:result
    endif

    if l:hash_pos >= 0 && (l:plain_pos < 0 || l:hash_pos < l:plain_pos)
        let l:hash_tail = strpart(l:text, l:hash_pos)
        let l:hash_end = matchend(l:hash_tail, '^' . l:hash_pat)
        if l:hash_end <= 0
            return l:result
        endif
        let l:param_open = l:hash_pos + l:hash_end - 1
        let l:param_close = s:FindMatchingParen(l:text, l:param_open)
        if l:param_close < 0
            return l:result
        endif
        let l:instance_tail = strpart(l:text, l:param_close + 1)
        let l:instance_end = matchend(l:instance_tail, '^\_s*\h\w*\_s*(')
        if l:instance_end <= 0
            return l:result
        endif
        let l:port_open = l:param_close + l:instance_end
    else
        let l:plain_tail = strpart(l:text, l:plain_pos)
        let l:plain_end = matchend(l:plain_tail, '^' . l:plain_pat)
        if l:plain_end <= 0
            return l:result
        endif
        let l:port_open = l:plain_pos + l:plain_end - 1
    endif

    let l:port_close = s:FindMatchingParen(l:text, l:port_open)
    if l:port_close < 0
        return l:result
    endif
    let l:ports = strpart(l:text, l:port_open + 1, l:port_close - l:port_open - 1)
    if l:ports =~# '^\_s*$'
        " An explicit empty list means no named child ports were connected.
        let l:result.recognized = 1
        return l:result
    endif

    if l:ports =~# '\.\*'
        let l:result.wildcard = 1
    endif

    " Positional connections cannot be mapped to child port names here.
    if l:ports !~# '\.\h\w*'
        return l:result
    endif

    let l:result.recognized = 1
    let l:psearch = 0
    while 1
        let l:pstart = match(l:ports, '\.\h\w*', l:psearch)
        if l:pstart < 0
            break
        endif
        let l:pname = matchstr(strpart(l:ports, l:pstart), '^\.\zs\h\w*')
        let l:after_name = l:pstart + 1 + strlen(l:pname)
        let l:tail = strpart(l:ports, l:after_name)
        let l:open_rel = match(l:tail, '^\_s*(')

        if l:open_rel < 0
            " SystemVerilog implicit named connection: .signal
            let l:result.ports[l:pname] = {'kind': 'match', 'conn': l:pname, 'exclude': 1}
            let l:psearch = l:after_name
            continue
        endif

        let l:open_abs = l:after_name + match(l:tail, '(')
        let l:conn_close = s:FindMatchingParen(l:ports, l:open_abs)
        if l:conn_close < 0
            break
        endif
        let l:conn = strpart(l:ports, l:open_abs + 1, l:conn_close - l:open_abs - 1)
        let l:conn = substitute(l:conn, '^\s*', '', '')
        let l:conn = substitute(l:conn, '\s*$', '', '')

        if empty(l:conn)
            let l:result.ports[l:pname] = {'kind': 'open', 'conn': '', 'exclude': 0}
        elseif l:conn =~# '^\h\w*$' && l:conn ==# l:pname
            " Exclude the actual signal occurrence here. The formal .port
            " label is removed separately by the precomputed formal-pin-label index.
            let l:result.ports[l:pname] = {'kind': 'match', 'conn': l:conn, 'exclude': 1}
        else
            let l:result.ports[l:pname] = {'kind': 'mismatch', 'conn': l:conn, 'exclude': 1}
        endif
        let l:psearch = l:conn_close + 1
    endwhile

    return l:result
endfunction

function! s:GetMismatchedConnections(module, body_start, body_end) abort
    " Compatibility helper: return all explicitly non-matching named ports.
    let l:bad = {}
    let l:connections = s:GetInstancePortConnections(a:module, a:body_start, a:body_end)
    for l:name in keys(l:connections.ports)
        if l:connections.ports[l:name].kind !=# 'match'
            let l:bad[l:name] = 1
        endif
    endfor
    return l:bad
endfunction

" -----------------------------------------------------------------------------
" Duplicate named-port connection detection.
"
" The scan is limited to the current parent module body and to instance port
" lists. Parameter override lists such as #(.WIDTH(WIDTH)) are not counted.
" All conditional-compilation branches are scanned as text; no macro
" exclusivity analysis is attempted.
" -----------------------------------------------------------------------------
function! s:AutoPortGetCodeText(lines) abort
    let l:text = join(a:lines, "\n")
    let l:out = ''
    let l:i = 0
    let l:n = strlen(l:text)
    let l:block_comment = 0
    let l:line_comment = 0
    let l:string = 0
    let l:escaped = 0

    while l:i < l:n
        let l:two = strpart(l:text, l:i, 2)
        let l:ch = strpart(l:text, l:i, 1)

        if l:line_comment
            if l:ch ==# "\n"
                let l:line_comment = 0
                let l:out .= "\n"
            else
                let l:out .= ' '
            endif
        elseif l:block_comment
            if l:two ==# '*/'
                let l:block_comment = 0
                let l:out .= '  '
                let l:i += 2
                continue
            elseif l:ch ==# "\n"
                let l:out .= "\n"
            else
                let l:out .= ' '
            endif
        elseif l:string
            if l:ch ==# "\n"
                let l:out .= "\n"
                let l:escaped = 0
            else
                let l:out .= ' '
                if l:escaped
                    let l:escaped = 0
                elseif l:ch ==# '\'
                    let l:escaped = 1
                elseif l:ch ==# '"'
                    let l:string = 0
                endif
            endif
        elseif l:two ==# '//'
            let l:line_comment = 1
            let l:out .= '  '
            let l:i += 2
            continue
        elseif l:two ==# '/*'
            let l:block_comment = 1
            let l:out .= '  '
            let l:i += 2
            continue
        elseif l:ch ==# '"'
            let l:string = 1
            let l:out .= ' '
        else
            let l:out .= l:ch
        endif

        let l:i += 1
    endwhile

    return l:out
endfunction

function! s:AutoPortCountNamedConnections(ports, counts) abort
    " Only count .name(name), not .name(expression) or .name().
    let l:pat = '\.\_s*\(\h\w*\)\_s*(\_s*\(\h\w*\)\_s*)'
    let l:search_from = 0
    while 1
        let l:pos = match(a:ports, l:pat, l:search_from)
        if l:pos < 0
            break
        endif

        let l:tail = strpart(a:ports, l:pos)
        let l:match = matchlist(l:tail, '^' . l:pat)
        let l:match_end = matchend(l:tail, '^' . l:pat)
        if len(l:match) >= 3 && l:match[1] ==# l:match[2]
            let a:counts[l:match[1]] = get(a:counts, l:match[1], 0) + 1
        endif

        if l:match_end <= 0
            let l:search_from = l:pos + 1
        else
            let l:search_from = l:pos + l:match_end
        endif
    endwhile
endfunction

function! s:AutoPortCountInstancePortLists(text, port_open, counts) abort
    " Count the first instance and any additional instances in a declaration
    " such as: child u0(...), u1(...);
    let l:open = a:port_open
    let l:scan_from = l:open
    while l:open >= 0
        let l:close = s:FindMatchingParen(a:text, l:open)
        if l:close < 0
            return l:scan_from
        endif

        let l:ports = strpart(a:text, l:open + 1, l:close - l:open - 1)
        call s:AutoPortCountNamedConnections(l:ports, a:counts)
        let l:scan_from = l:close + 1

        " Verilog permits multiple instance declarators after one module type.
        let l:tail = strpart(a:text, l:scan_from)
        let l:comma_end = matchend(l:tail, '^\_s*,\_s*')
        if l:comma_end <= 0
            break
        endif
        let l:instance_tail = strpart(l:tail, l:comma_end)
        let l:instance_end = matchend(l:instance_tail, '^\h\w*\_s*(')
        if l:instance_end <= 0
            break
        endif
        let l:open = l:scan_from + l:comma_end + l:instance_end - 1
    endwhile

    return l:scan_from
endfunction

function! s:AutoPortFindDuplicateConnections(body_start, body_end, ...) abort
    let l:duplicates = {}
    if a:body_start > a:body_end
        return l:duplicates
    endif

    let l:text = a:0 >= 1 ? a:1 : s:AutoPortGetCodeText(getline(a:body_start, a:body_end))
    let l:counts = {}
    let l:search_from = 0
    let l:plain_pat = '\<\h\w*\>\_s\+\h\w*\_s*('
    let l:hash_pat = '\<\h\w*\>\_s*#\_s*('

    while l:search_from < strlen(l:text)
        let l:plain_pos = match(l:text, l:plain_pat, l:search_from)
        let l:hash_pos = match(l:text, l:hash_pat, l:search_from)
        if l:plain_pos < 0 && l:hash_pos < 0
            break
        endif

        if l:hash_pos >= 0 && (l:plain_pos < 0 || l:hash_pos < l:plain_pos)
            " Parameterized instance: module_type #(...) instance_name (...).
            let l:hash_tail = strpart(l:text, l:hash_pos)
            let l:hash_end = matchend(l:hash_tail, '^' . l:hash_pat)
            if l:hash_end <= 0
                let l:search_from = l:hash_pos + 1
                continue
            endif
            let l:param_open = l:hash_pos + l:hash_end - 1
            let l:param_close = s:FindMatchingParen(l:text, l:param_open)
            if l:param_close < 0
                break
            endif

            let l:instance_tail = strpart(l:text, l:param_close + 1)
            let l:instance_pat = '^\_s*\h\w*\_s*('
            let l:instance_end = matchend(l:instance_tail, l:instance_pat)
            if l:instance_end <= 0
                let l:search_from = l:param_close + 1
                continue
            endif
            let l:port_open = l:param_close + l:instance_end
        else
            " Non-parameterized instance: module_type instance_name (...).
            let l:plain_tail = strpart(l:text, l:plain_pos)
            let l:plain_end = matchend(l:plain_tail, '^' . l:plain_pat)
            if l:plain_end <= 0
                let l:search_from = l:plain_pos + 1
                continue
            endif
            let l:port_open = l:plain_pos + l:plain_end - 1
        endif

        let l:next_search = s:AutoPortCountInstancePortLists(l:text, l:port_open, l:counts)
        if l:next_search <= l:search_from
            let l:search_from = l:port_open + 1
        else
            let l:search_from = l:next_search
        endif
    endwhile

    for l:name in keys(l:counts)
        if l:counts[l:name] >= 2
            let l:duplicates[l:name] = l:counts[l:name]
        endif
    endfor

    return l:duplicates
endfunction

function! s:AutoPortDuplicateComment(line) abort
    let l:code = s:StripComments([a:line])[0]
    let l:code = substitute(l:code, '^\s*', '', '')
    let l:code = substitute(l:code, '\s*$', '', '')
    let l:code = substitute(l:code, ',\s*$', '', '')
    if empty(l:code)
        return ''
    endif
    return repeat(' ', max([0, g:atv_autoport_st_pos])) . '// AUTOPORT_DUPLICATE: ' . l:code
endfunction

function! s:AutoPortUnusedComment(line, detail) abort
    let l:code = s:StripComments([a:line])[0]
    let l:code = substitute(l:code, '^\s*', '', '')
    let l:code = substitute(l:code, '\s*$', '', '')
    let l:code = substitute(l:code, ',\s*$', '', '')
    if empty(l:code)
        return ''
    endif

    let l:line_comment_pos = match(a:line, '//')
    let l:block_pos = match(a:line, '/\*')
    if l:block_pos >= 0 && l:line_comment_pos >= 0 && l:line_comment_pos < l:block_pos
        " A block-comment token inside a // comment is only text.
        let l:block_pos = -1
    endif
    let l:comment_pos = l:line_comment_pos
    if l:block_pos >= 0 && (l:comment_pos < 0 || l:block_pos < l:comment_pos)
        let l:comment_pos = l:block_pos
    endif
    let l:comment = l:comment_pos >= 0 ? ' ' . strpart(a:line, l:comment_pos) : ''
    if l:block_pos >= 0 && match(a:line, '\*/', l:block_pos + 2) < 0
        " The block continues on following source lines; it is emitted as a
        " separate block comment by AutoPortUnusedCommentLines().
        let l:comment = ''
    endif
    return repeat(' ', max([0, g:atv_autoport_st_pos]))
                \ . '// AUTOPORT_UNUSED: ' . l:code . a:detail . l:comment
endfunction

function! s:AutoPortUnusedCommentLines(line, detail) abort
    let l:out = [s:AutoPortUnusedComment(a:line, a:detail)]
    let l:line_comment_pos = match(a:line, '//')
    let l:block_pos = match(a:line, '/\*')
    if l:block_pos >= 0 && l:line_comment_pos >= 0 && l:line_comment_pos < l:block_pos
        let l:block_pos = -1
    endif
    if l:block_pos >= 0 && match(a:line, '\*/', l:block_pos + 2) < 0
        call add(l:out, repeat(' ', max([0, g:atv_autoport_st_pos]))
                    \ . strpart(a:line, l:block_pos))
    endif
    return filter(l:out, '!empty(v:val)')
endfunction

function! s:AutoPortBuildSignalUsageIndex(body_start, body_end, header_before, ...) abort
    " Build all signal-usage information in one parent-module pass.
    " The previous implementation rescanned and retokenized the full module
    " once per candidate port, making large AUTOPORT blocks unnecessarily slow.
    let l:index = {
                \ 'identifier_counts': {},
                \ 'declared_counts': {},
                \ 'formal_pin_counts': {},
                \ 'header_ports': {}
                \ }

    " A hand-written module-header port is an external connection and must
    " prevent AUTOPORT_UNUSED, even without another textual body reference.
    for l:line in a:header_before
        let l:name = s:PortNameFromLine(l:line)
        if !empty(l:name)
            let l:index.header_ports[l:name] = 1
        endif
    endfor

    if a:body_start > a:body_end
        return l:index
    endif

    let l:raw_lines = a:0 >= 2 ? a:2 : getline(a:body_start, a:body_end)
    let l:text = a:0 >= 1 ? a:1 : s:AutoPortGetCodeText(l:raw_lines)

    " Count every code identifier once. Comments and strings have already
    " been blanked by AutoPortGetCodeText(), while line structure is retained.
    let l:pos = 0
    while 1
        let l:found = match(l:text, '\h\w*', l:pos)
        if l:found < 0
            break
        endif
        let l:name = matchstr(l:text, '\h\w*', l:pos)
        let l:index.identifier_counts[l:name] =
                    \ get(l:index.identifier_counts, l:name, 0) + 1
        let l:end = matchend(l:text, '\h\w*', l:pos)
        if l:end <= l:pos
            break
        endif
        let l:pos = l:end
    endwhile

    " Declarations are not uses by themselves. Reuse the per-line counts
    " already collected during conflict analysis when the caller supplies them.
    if a:0 >= 3
        let l:index.declared_counts = copy(a:3)
    else
        for l:line in l:raw_lines
            for l:name in s:DeclaredNamesFromLine(l:line)
                let l:index.declared_counts[l:name] =
                            \ get(l:index.declared_counts, l:name, 0) + 1
            endfor
        endfor
    endif

    " In `.formal(actual)`, the formal pin label is not a parent signal use.
    " Count formal labels once so a query for any candidate is O(1).
    let l:formal_pat = '\.\_s*\zs\h\w*\ze\_s*('
    let l:pos = 0
    while 1
        let l:found = match(l:text, l:formal_pat, l:pos)
        if l:found < 0
            break
        endif
        let l:name = matchstr(l:text, l:formal_pat, l:pos)
        let l:index.formal_pin_counts[l:name] =
                    \ get(l:index.formal_pin_counts, l:name, 0) + 1
        let l:end = matchend(l:text, l:formal_pat, l:pos)
        if l:end <= l:pos
            break
        endif
        let l:pos = l:end
    endwhile

    return l:index
endfunction

function! s:AutoPortSignalHasOtherUse(index, signal, connection_refs) abort
    " Look up the precomputed index. The target-instance signal occurrence
    " and all formal `.pin(...)` labels are excluded; declarations alone are
    " not uses. Any remaining identifier occurrence counts as another use,
    " including both sides of assign, all references in always blocks, and
    " actual connections to other module ports.
    if a:signal !~# '^\h\w*$'
        return 1
    endif

    if has_key(a:index.header_ports, a:signal)
        return 1
    endif

    let l:uses = get(a:index.identifier_counts, a:signal, 0)
                \ - get(a:index.declared_counts, a:signal, 0)
                \ - a:connection_refs
                \ - get(a:index.formal_pin_counts, a:signal, 0)
    return l:uses > 0
endfunction

function! s:AutoPortHasLaterRegionPorts(boundary, header_close, conflicts, duplicates, body_start, body_end, ...) abort
    if a:boundary.kind !=# 'marker'
        return 0
    endif

    let l:line_nr = a:boundary.line
    let l:start_col = a:boundary.col
    while l:line_nr <= a:header_close[0]
        let l:line = getline(l:line_nr)
        let l:pos = match(l:line, s:autop_marker_pat, l:start_col)
        if l:pos < 0 || (l:line_nr == a:header_close[0] && l:pos >= a:header_close[1])
            let l:line_nr += 1
            let l:start_col = 0
            continue
        endif

        if l:line !~ '^\s*//'
            let l:marker = matchstr(strpart(l:line, l:pos), '^' . s:autop_marker_pat)
            let l:module = matchstr(l:marker, '(\s*\zs\h\w*\ze\s*)')
            if !empty(l:module)
                let l:source_file = s:FindModuleFile(l:module)
                if !empty(l:source_file) && filereadable(l:source_file)
                    let l:src_body = s:GetModulePortBody(readfile(l:source_file), l:module)
                    if !empty(l:src_body)
                        let l:clean_src = s:StripComments(l:src_body)
                        let l:connections = a:0 >= 1
                                    \ ? s:GetInstancePortConnections(l:module, a:body_start, a:body_end, a:1)
                                    \ : s:GetInstancePortConnections(l:module, a:body_start, a:body_end)
                        let l:mismatches = {}
                        for l:name in keys(l:connections.ports)
                            if l:connections.ports[l:name].kind !=# 'match'
                                let l:mismatches[l:name] = 1
                            endif
                        endfor
                        for l:src_line in l:clean_src
                            let l:pname = s:PortNameFromLine(l:src_line)
                            if !empty(l:pname)
                                        \ && !has_key(a:conflicts, l:pname)
                                        \ && !has_key(a:duplicates, l:pname)
                                        \ && !has_key(l:mismatches, l:pname)
                                        \ && !(l:connections.recognized && !l:connections.wildcard
                                        \       && !has_key(l:connections.ports, l:pname))
                                return 1
                            endif
                        endfor
                    endif
                endif
            endif
        endif

        let l:start_col = l:pos + strlen(l:marker)
    endwhile

    return 0
endfunction
