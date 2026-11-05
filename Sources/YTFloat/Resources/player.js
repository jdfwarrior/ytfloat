'use strict';
(() => {
  let player, ready = false, request, settings = {}, scriptStarted = false, scriptTimer, nextAutoplay;
  let savedVolume = 100, savedMuted = false;
  const $ = id => document.getElementById(id);
  const post = (event, extra = {}) => window.webkit?.messageHandlers.player.postMessage({event, ...extra});
  const showError = (title, detail) => {
    $('notice-title').textContent = title; $('notice-detail').textContent = detail;
    $('notice').hidden = false; $('play').hidden = true;
  };
  function load() {
    if (!ready || !request) return;
    $('welcome').hidden = true; $('notice').hidden = true; $('play').hidden = true;
    const video = {videoId:request.id, startSeconds:request.start};
    const autoplay = nextAutoplay ?? settings.autoplay;
    nextAutoplay = undefined;
    if (autoplay) player.loadVideoById(video); else player.cueVideoById(video);
  }
  function createPlayer() {
    if (!request) return;
    clearTimeout(scriptTimer);
    if (player) {
      if (ready) { savedVolume = player.getVolume(); savedMuted = player.isMuted(); }
      player.destroy();
    }
    ready = false;
    $('welcome').hidden = true;
    // Use an explicit iframe so referrerpolicy is set before its first network request.
    const frame = document.createElement('iframe'); frame.id = 'player';
    frame.title = 'YouTube video player';
    frame.referrerPolicy = 'strict-origin-when-cross-origin';
    frame.allow = 'autoplay; encrypted-media; picture-in-picture; fullscreen';
    const params = new URLSearchParams({enablejsapi:'1', origin:location.origin,
      widget_referrer:location.href, controls:settings.showControls ? '1' : '0',
      playsinline:'1', fs:'0', rel:'0', autoplay:'0'});
    frame.src = `https://www.youtube.com/embed/${request.id}?${params}`;
    const placeholder = $('player');
    if (placeholder) placeholder.replaceWith(frame); else document.body.prepend(frame);
    player = new YT.Player(frame, {events:{
      onReady() {
        ready = true; clearTimeout(scriptTimer);
        player.setVolume(savedVolume);
        if (savedMuted) player.mute();
        post('ready'); load();
      },
      onStateChange(e) {
        $('play').hidden = true;
        const data = player.getVideoData();
        post('state', {state:e.data, title:data.title || '', videoID:data.video_id || request?.id || ''});
      },
      onAutoplayBlocked() { $('play').hidden = false; post('autoplayBlocked'); },
      onError(e) {
        const reasons = {
          2:'This video link is invalid.', 5:'WebKit could not play this video. Try opening it on YouTube.',
          100:'This video is private, removed, or unavailable.',
          101:'The owner has disabled playback in embedded players.',
          150:'The owner has disabled playback in embedded players.',
          153:'YouTube rejected this player’s origin or referrer. Try again, or open the video on YouTube.'
        };
        showError('This video can’t play here', reasons[e.data] || `YouTube returned error ${e.data}.`);
        post('error', {code:e.data});
      }
    }});
    scriptTimer = setTimeout(() => {
      if (!ready) { showError('Still waiting for YouTube', 'Check your connection, then try again.'); post('networkError'); }
    }, 20000);
  }
  window.onYouTubeIframeAPIReady = createPlayer;
  function startAPI() {
    if (window.YT?.Player) { createPlayer(); return; }
    if (scriptStarted) return;
    scriptStarted = true;
    const script = document.createElement('script'); script.src = 'https://www.youtube.com/iframe_api';
    script.onerror = () => { scriptStarted = false; showError('YouTube is unreachable', 'Check your connection and try again.'); post('networkError'); };
    document.head.append(script);
    clearTimeout(scriptTimer);
    scriptTimer = setTimeout(() => {
      if (!ready) { scriptStarted = false; showError('Still waiting for YouTube', 'Check your connection, then try again.'); post('networkError'); }
    }, 20000);
  }
  window.YTFloat = {
    open(video, preferences) {
      const changedControls = settings.showControls !== preferences.showControls;
      request = video; settings = preferences; nextAutoplay = undefined;
      $('welcome').hidden = true; $('notice').hidden = true;
      if (ready && !changedControls) load(); else startAPI();
    },
    configure(preferences) {
      const changed = settings.showControls !== preferences.showControls;
      settings = preferences;
      if (changed && ready && request) {
        request = {...request, start:Math.floor(player.getCurrentTime() || request.start)};
        nextAutoplay = player.getPlayerState() === 1;
        createPlayer();
      }
    },
    toggle() { if (ready) player.getPlayerState() === 1 ? player.pauseVideo() : player.playVideo(); },
    seek(delta) { if (ready) player.seekTo(Math.max(0, player.getCurrentTime() + delta), true); },
    pause() { if (ready) player.pauseVideo(); }
  };
  $('open').onclick = () => post('open');
  $('play').onclick = () => player?.playVideo();
  $('retry').onclick = () => { $('notice').hidden = true; startAPI(); };
  $('external').onclick = () => post('external');
  document.addEventListener('keydown', e => {
    if ((e.metaKey || e.ctrlKey) && ['o','v',',','w','q'].includes(e.key.toLowerCase())) return;
    if (e.code === 'Space' && ready && e.target.tagName !== 'BUTTON') { e.preventDefault(); window.YTFloat.toggle(); }
  });
  // Only the local top frame owns the bridge; no polling is needed for playback state.
  post('pageReady', {origin:location.origin});
})();
