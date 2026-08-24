String buildTeamInviteUrl(String joinCode, {Uri? baseUri}) {
  final base = baseUri ?? Uri.base;
  return base
      .replace(path: '/', queryParameters: {'join': joinCode})
      .removeFragment()
      .toString();
}
