function ticklab = colorbarFixTickLabel(cb, limit)
% ticklab = colorbarFixTickLabel(cb, limit)
%
% Fix colorbar tick labels when the colour axis (clim) does not span the
% full data range.  Adds ≤ to the lowest tick and/or ≥ to the highest tick
% to signal that data extend beyond the displayed range.
%
% INPUTS
%   cb     Handle to the colorbar
%   limit  Which end(s) to annotate:
%            'auto'   (default) — inspect the image data in the parent axes
%                     and add ≤/≥ only where clim clips the actual data range
%            'both'  — add ≤ at bottom and ≥ at top unconditionally
%            'lower' (or 'l') — add ≤ at bottom only
%            'upper' (or 'u') — add ≥ at top only
%
% OUTPUTS
%   ticklab  Cell array of tick label strings (also applied to the colorbar)

if nargin < 2 || isempty(limit)
    limit = 'auto';
end

% Determine whether the colorbar labels are on the x or y axis
if isempty(get(cb, 'YTick'))
    axProp      = 'xtick';
    axLabelProp = 'xticklabel';
else
    axProp      = 'ytick';
    axLabelProp = 'yticklabel';
end

tick    = get(cb, axProp);
ticklab = cellstr(num2str(tick(:)));

% Auto mode: compare clim with the actual data range of the image in the
% parent axes.  Works with any imagesc/image call since CData is accessible
% via the child image object.
if strcmpi(limit, 'auto')
    % cb.Parent may be a TiledChartLayout rather than axes when colorbars
    % are created inside tiledlayout figures — walk up until we find axes.
    axH = cb.Parent;
    while ~isempty(axH) && ~isa(axH, 'matlab.graphics.axis.Axes')
        if isprop(axH, 'Parent')
            axH = axH.Parent;
        else
            axH = [];
        end
    end
    imgH = [];
    if ~isempty(axH)
        imgH = findobj(axH, 'Type', 'image');
    end
    if ~isempty(imgH)
        cdata    = get(imgH(1), 'CData');
        dataMin  = min(cdata(:));
        dataMax  = max(cdata(:));
        clim     = get(axH, 'CLim');
        doLower  = clim(1) > dataMin;
        doUpper  = clim(2) < dataMax;
    else
        % No image found — fall back to annotating both ends
        doLower = true;
        doUpper = true;
    end
    if doLower, ticklab{1}   = [char(8804) ticklab{1}];  end   % ≤
    if doUpper, ticklab{end} = [char(8805) ticklab{end}]; end   % ≥
else
    switch lower(limit)
        case {'lower', 'l'}
            ticklab{1}   = [char(8804) ticklab{1}];
        case {'upper', 'u'}
            ticklab{end} = [char(8805) ticklab{end}];
        otherwise   % 'both' or unrecognised
            ticklab{1}   = [char(8804) ticklab{1}];
            ticklab{end} = [char(8805) ticklab{end}];
    end
end

set(cb, axLabelProp, ticklab);

end
